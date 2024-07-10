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
import { BookmarkService } from '../src/bookmark/bookmark.service';
import { MongoIdDto } from '../src/common/mongoid.dto';
import { ContentService } from '../src/content/content.service';
import { CreateContentDto } from '../src/content/dto/create-content.dto';
import { Category, Content } from '../src/content/schemas/content.schema';

describe('Bookmark Controller - (e2e)', () => {
  let app: INestApplication;
  let userService: UserService;
  let authService: AuthService;
  let contentService: ContentService;
  let bookmarkService: BookmarkService;

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
    bookmarkService = module.get(BookmarkService);

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

    await app.init();
  });

  afterEach(async () => {
    await authService.deleteApiKey(apiKey);
    await authService.deleteRole(role);
    await userService.delete(userAuthDto.user as User);
    await bookmarkService.deleteUserBookmarks(userAuthDto.user as User);
    await contentService.deleteFromDb(content);
    await authService.signOutFromEverywhere(userAuthDto.user as User);
    await app.close();
  });

  it('should not bookmark private content', async () => {
    const mongoIdDto = new MongoIdDto({
      id: content._id,
    });

    await request(app.getHttpServer())
      .post('/content/bookmark')
      .set('Content-Type', 'application/json')
      .set('x-api-key', apiKey.key)
      .set('Authorization', `Bearer ${userAuthDto.tokens.accessToken}`)
      .send(mongoIdDto)
      .expect(403)
      .expect(async (response) => {
        expect(response.body.statusCode).toEqual(StatusCode.FAILURE);
        expect(response.body.message).toEqual('Content Not Avilable');
      });
  });

  it('should bookmark general content', async () => {
    const mongoIdDto = new MongoIdDto({
      id: content._id,
    });

    await contentService.publishContent(userAuthDto.user as User, content._id);

    await request(app.getHttpServer())
      .post('/content/bookmark')
      .set('Content-Type', 'application/json')
      .set('x-api-key', apiKey.key)
      .set('Authorization', `Bearer ${userAuthDto.tokens.accessToken}`)
      .send(mongoIdDto)
      .expect(201)
      .expect(async (response) => {
        expect(response.body.statusCode).toEqual(StatusCode.SUCCESS);
        expect(response.body.message).toEqual(
          'Content bookmarked successfully',
        );
      });
  });

  it('should send error when bookmark was not created', async () => {
    await contentService.publishContent(userAuthDto.user as User, content._id);

    await request(app.getHttpServer())
      .delete(`/content/bookmark/id/${content._id}`)
      .set('Content-Type', 'application/json')
      .set('x-api-key', apiKey.key)
      .set('Authorization', `Bearer ${userAuthDto.tokens.accessToken}`)
      .expect(400)
      .expect(async (response) => {
        expect(response.body.statusCode).toEqual(StatusCode.FAILURE);
        expect(response.body.message).toEqual('Bookmark Not Found');
      });
  });

  it('should remove bookmark successfully', async () => {
    await contentService.publishContent(userAuthDto.user as User, content._id);
    await bookmarkService.create(userAuthDto.user as User, content._id);

    await request(app.getHttpServer())
      .delete(`/content/bookmark/id/${content._id}`)
      .set('Content-Type', 'application/json')
      .set('x-api-key', apiKey.key)
      .set('Authorization', `Bearer ${userAuthDto.tokens.accessToken}`)
      .expect(200)
      .expect(async (response) => {
        expect(response.body.statusCode).toEqual(StatusCode.SUCCESS);
        expect(response.body.message).toEqual('Bookmark deleted successfully');
      });
  });
});
