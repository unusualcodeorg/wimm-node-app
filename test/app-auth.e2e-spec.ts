import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import * as request from 'supertest';
import { AppModule } from '../src/app.module';
import { StatusCode } from '../src/core/http/response';
import { ApiKey, Permission } from '../src/auth/schemas/apikey.schema';
import { UserService } from '../src/user/user.service';
import { AuthService } from '../src/auth/auth.service';
import { Role, RoleCode } from '../src/auth/schemas/role.schema';

describe('AppController - AUTH (e2e)', () => {
  let app: INestApplication;
  let userService: UserService;
  let authService: AuthService;
  let apiKey: ApiKey;
  let role: Role;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    userService = module.get(UserService);
    authService = module.get(AuthService);
    app = module.createNestApplication();

    apiKey = await authService.createApiKey({
      key: 'test_api_key',
      version: 1,
      permissions: [Permission.GENERAL],
      comments: ['For testing'],
    });

    role = await authService.createRole({
      code: RoleCode.VIEWER,
    });

    await app.init();
  });

  afterEach(async () => {
    await authService.deleteApiKey(apiKey);
    await authService.deleteRole(role);
    await app.close();
  });

  it('should throw 401 when Authorization is not provided', () => {
    return request(app.getHttpServer())
      .get('/mentors/latest?pageNumber=1&pageItemCount=10')
      .set('Content-Type', 'application/json')
      .set('x-api-key', apiKey.key)
      .expect(401)
      .expect((response) => {
        expect(response.body.statusCode).toEqual(StatusCode.FAILURE);
        expect(response.body.message).toEqual('Unauthorized');
      });
  });

  it('should throw 401 when invalid auth token is sent', () => {
    return request(app.getHttpServer())
      .get('/mentors/latest?pageNumber=1&pageItemCount=10')
      .set('Content-Type', 'application/json')
      .set('x-api-key', apiKey.key)
      .set('Authorization', 'Bearer wrong_access_token')
      .expect(401)
      .expect((response) => {
        expect(response.body.statusCode).toEqual(
          StatusCode.INVALID_ACCESS_TOKEN,
        );
        expect(response.body.message).toEqual('Invalid Access Token');
      });
  });

  it('should send 200 when corrent auth token is sent', async () => {
    const signUp = await authService.signUpBasic({
      email: 'test@test.com',
      password: 'test123',
      name: 'test',
    });

    try {
      await request(app.getHttpServer())
        .get('/mentors/latest?pageNumber=1&pageItemCount=10')
        .set('Content-Type', 'application/json')
        .set('x-api-key', apiKey.key)
        .set('Authorization', `Bearer ${signUp.tokens.accessToken}`)
        .expect(200)
        .expect((response) => {
          expect(response.body.statusCode).toEqual(StatusCode.SUCCESS);
        });
    } finally {
      await userService.delete(signUp.user);
      await authService.signOutFromEverywhere(signUp.user);
    }
  });
});
