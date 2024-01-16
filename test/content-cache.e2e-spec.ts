import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import * as request from 'supertest';
import { AppModule } from '../src/app.module';
import { StatusCode } from '../src/core/http/response';
import { ApiKey, Permission } from '../src/core/schemas/apikey.schema';
import { CoreService } from '../src/core/core.service';
import { UserService } from '../src/user/user.service';
import { AuthService } from '../src/auth/auth.service';
import { Role, RoleCode } from '../src/auth/schemas/role.schema';
import { UserAuthDto } from '../src/auth/dto/user-auth.dto';
import { User } from '../src/user/schemas/user.schema';
import { ContentService } from '../src/content/content.service';
import { CreateContentDto } from '../src/content/dto/create-content.dto';
import { Category } from '../src/content/schemas/content.schema';
import { ContentInfoDto } from '../src/content/dto/content-info.dto';
import { CacheService } from '../src/cache/cache.service';

describe('Content Controller - Cache (e2e)', () => {
  let app: INestApplication;
  let coreService: CoreService;
  let userService: UserService;
  let authService: AuthService;
  let contentService: ContentService;
  let cacheService: CacheService;

  let userAuthDto: UserAuthDto;
  let apiKey: ApiKey;
  let role: Role;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    coreService = module.get(CoreService);
    userService = module.get(UserService);
    authService = module.get(AuthService);
    contentService = module.get(ContentService);
    cacheService = module.get(CacheService);

    app = module.createNestApplication();

    apiKey = await coreService.createApiKey({
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

    await app.init();
  });

  afterEach(async () => {
    await coreService.deleteApiKey(apiKey);
    await authService.deleteRole(role);
    await userService.delete(userAuthDto.user as User);
    await authService.signOutFromEverywhere(userAuthDto.user as User);
    await app.close();
  });

  it('should sent the content with id', async () => {
    const user = userAuthDto.user as User;
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

    const content = await contentService.createContent(createContentDto, user);

    await contentService.publishContent(user, content._id);
    contentService.statsBoostUp(content);

    content.createdBy = user;

    const contentInfoDto = new ContentInfoDto(content, false);
    delete contentInfoDto.private;
    delete contentInfoDto.description;

    const createdBy = {
      ...contentInfoDto.createdBy,
      _id: contentInfoDto.createdBy._id.toHexString(),
    };
    const data = {
      ...contentInfoDto,
      _id: contentInfoDto._id.toHexString(),
      createdBy: createdBy,
    };

    try {
      await request(app.getHttpServer())
        .get(`/content/id/${data._id}`)
        .set('Content-Type', 'application/json')
        .set('x-api-key', apiKey.key)
        .set('Authorization', `Bearer ${userAuthDto.tokens.accessToken}`)
        .expect(200)
        .expect((response) => {
          expect(response.body.statusCode).toEqual(StatusCode.SUCCESS);
          expect(response.body.data).not.toBeNull();
          expect(response.body.data).toEqual(data);
        });
      const cached = await cacheService.getValue(`/content/id/${data._id}`);
      expect(cached).toEqual(data);
    } finally {
      await contentService.deleteFromDb(content);
    }
  });
});
