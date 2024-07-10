import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import * as request from 'supertest';
import { AppModule } from '../src/app.module';
import { StatusCode } from '../src/core/http/response';
import { Permission } from '../src/auth/schemas/apikey.schema';
import { AuthService } from '../src/auth/auth.service';

describe('AppController - API KEY (e2e)', () => {
  let app: INestApplication;
  let authService: AuthService;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    authService = module.get(AuthService);
    app = module.createNestApplication();

    await app.init();
  });

  afterEach(async () => {
    await app.close();
  });

  it('should throw 403 when x-api-key is not provided', () => {
    return request(app.getHttpServer())
      .get('/mentors/latest?pageNumber=1&pageItemCount=10')
      .expect(403)
      .expect((response) => {
        expect(response.body.statusCode).toEqual(StatusCode.FAILURE);
        expect(response.body.message).toEqual('Forbidden');
      });
  });

  it('should throw 403 when wrong x-api-key is provided', async () => {
    const apiKey = await authService.createApiKey({
      key: 'test_api_key',
      version: 1,
      permissions: [Permission.GENERAL],
      comments: ['For testing'],
    });

    try {
      await request(app.getHttpServer())
        .get('/mentors/latest?pageNumber=1&pageItemCount=10')
        .set('Content-Type', 'application/json')
        .set('x-api-key', 'wrong_api_key')
        .expect(403)
        .expect((response) => {
          expect(response.body.statusCode).toEqual(StatusCode.FAILURE);
          expect(response.body.message).toEqual('Forbidden');
        });
    } finally {
      await authService.deleteApiKey(apiKey);
    }
  });

  it('should throw 403 when x-api-key does not have right permissions', async () => {
    const apiKey = await authService.createApiKey({
      key: 'test_api_key_1',
      version: 1,
      permissions: [Permission.XYZ_SERVICE],
      comments: ['For testing'],
    });

    try {
      await request(app.getHttpServer())
        .get('/mentors/latest?pageNumber=1&pageItemCount=10')
        .set('Content-Type', 'application/json')
        .set('x-api-key', apiKey.key)
        .expect(403)
        .expect((response) => {
          expect(response.body.statusCode).toEqual(StatusCode.FAILURE);
          expect(response.body.message).toEqual('Forbidden');
        });
    } finally {
      await authService.deleteApiKey(apiKey);
    }
  });

  it('should throw 401 when correct x-api-key is provided', async () => {
    const apiKey = await authService.createApiKey({
      key: 'test_api_key_2',
      version: 1,
      permissions: [Permission.GENERAL],
      comments: ['For testing'],
    });

    try {
      await request(app.getHttpServer())
        .get('/mentors/latest?pageNumber=1&pageItemCount=10')
        .set('Content-Type', 'application/json')
        .set('x-api-key', apiKey.key)
        .expect(401)
        .expect((response) => {
          expect(response.body.statusCode).toEqual(StatusCode.FAILURE);
          expect(response.body.message).toEqual('Unauthorized');
        });
    } finally {
      await authService.deleteApiKey(apiKey);
    }
  });

  it('should send 200 when correct x-api-key is provided for heartbeat', async () => {
    const apiKey = await authService.createApiKey({
      key: 'test_api_key_3',
      version: 1,
      permissions: [Permission.GENERAL],
      comments: ['For testing'],
    });

    try {
      await request(app.getHttpServer())
        .get('/heartbeat')
        .set('Content-Type', 'application/json')
        .set('x-api-key', apiKey.key)
        .expect(200)
        .expect((response) => {
          expect(response.body.statusCode).toEqual(StatusCode.SUCCESS);
          expect(response.body.message).toEqual('alive');
        });
    } finally {
      await authService.deleteApiKey(apiKey);
    }
  });
});
