import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import * as request from 'supertest';
import { AppModule } from '../src/app.module';
import { StatusCode } from '../src/core/http/response';
import { ApiKey, Permission } from '../src/auth/schemas/apikey.schema';
import { UserService } from '../src/user/user.service';
import { AuthService } from '../src/auth/auth.service';
import { Role, RoleCode } from '../src/auth/schemas/role.schema';
import { UserAuthDto } from '../src/auth/dto/user-auth.dto';
import { User } from '../src/user/schemas/user.schema';
import { ContentService } from '../src/content/content.service';
import { CreateContentDto } from '../src/content/dto/create-content.dto';
import { Category, Content } from '../src/content/schemas/content.schema';
import { MongoIdDto } from '../src/common/mongoid.dto';

describe('Content Controller - (e2e)', () => {
  let app: INestApplication;
  let userService: UserService;
  let authService: AuthService;
  let contentService: ContentService;

  let userAuthDto: UserAuthDto;
  let apiKey: ApiKey;
  let role: Role;
  let content: Content;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    userService = module.get(UserService);
    authService = module.get(AuthService);
    contentService = module.get(ContentService);

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

    userAuthDto = await authService.signUpBasic({
      email: 'test@test.com',
      password: 'test123',
      name: 'test',
      profilePicUrl: 'https://user.com/profilePicUrl.png',
    });

    const createContentDto = new CreateContentDto({
      category: Category.YOUTUBE,
      title: 'content_title',
      subtitle: 'content_subtitle',
      description: 'content_description',
      thumbnail: 'https://content.com/thumbnail.png',
      extra: 'https://content.com/coverImgUrl.png',
      topics: [],
      mentors: [],
      score: 0.1,
    });

    content = await contentService.createContent(
      createContentDto,
      userAuthDto.user as User,
    );

    await contentService.publishContent(userAuthDto.user as User, content._id);

    await app.init();
  });

  afterEach(async () => {
    await authService.deleteApiKey(apiKey);
    await authService.deleteRole(role);
    await userService.delete(userAuthDto.user as User);
    await contentService.deleteFromDb(content);
    await authService.signOutFromEverywhere(userAuthDto.user as User);
    await app.close();
  });

  it('should mark the content as views', async () => {
    const mongoIdDto = new MongoIdDto({ id: content._id });

    await request(app.getHttpServer())
      .post('/content/mark/view')
      .set('Content-Type', 'application/json')
      .set('x-api-key', apiKey.key)
      .set('Authorization', `Bearer ${userAuthDto.tokens.accessToken}`)
      .send(mongoIdDto)
      .expect(201)
      .expect(async (response) => {
        expect(response.body.statusCode).toEqual(StatusCode.SUCCESS);
        expect(response.body.message).toMatch(
          /Content view marked successfully/,
        );
      });
  });

  it('should like the content ', async () => {
    const mongoIdDto = new MongoIdDto({ id: content._id });

    await request(app.getHttpServer())
      .post('/content/mark/like')
      .set('Content-Type', 'application/json')
      .set('x-api-key', apiKey.key)
      .set('Authorization', `Bearer ${userAuthDto.tokens.accessToken}`)
      .send(mongoIdDto)
      .expect(201)
      .expect(async (response) => {
        expect(response.body.statusCode).toEqual(StatusCode.SUCCESS);
        expect(response.body.message).toMatch(/Content liked successfully/);
      });
  });

  it('should like the content ', async () => {
    const mongoIdDto = new MongoIdDto({ id: content._id });
    await contentService.markLike(content._id, userAuthDto.user as User);

    await request(app.getHttpServer())
      .post('/content/mark/unlike')
      .set('Content-Type', 'application/json')
      .set('x-api-key', apiKey.key)
      .set('Authorization', `Bearer ${userAuthDto.tokens.accessToken}`)
      .send(mongoIdDto)
      .expect(201)
      .expect(async (response) => {
        expect(response.body.statusCode).toEqual(StatusCode.SUCCESS);
        expect(response.body.message).toMatch(
          /Content like removed successfully/,
        );
      });
  });

  it('should mark the content as shared', async () => {
    const mongoIdDto = new MongoIdDto({ id: content._id });

    await request(app.getHttpServer())
      .post('/content/mark/share')
      .set('Content-Type', 'application/json')
      .set('x-api-key', apiKey.key)
      .set('Authorization', `Bearer ${userAuthDto.tokens.accessToken}`)
      .send(mongoIdDto)
      .expect(201)
      .expect(async (response) => {
        expect(response.body.statusCode).toEqual(StatusCode.SUCCESS);
        expect(response.body.message).toMatch(
          /Content share marked successfully/,
        );
      });
  });
});
