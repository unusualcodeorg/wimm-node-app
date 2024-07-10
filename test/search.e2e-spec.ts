import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import * as request from 'supertest';
import { AppModule } from '../src/app.module';
import { StatusCode } from '../src/core/http/response';
import { ApiKey, Permission } from '../src/auth/schemas/apikey.schema';
import { UserService } from '../src/user/user.service';
import { AuthService } from '../src/auth/auth.service';
import { Role, RoleCode } from '../src/auth/schemas/role.schema';
import { TopicService } from '../src/topic/topic.service';
import { UserAuthDto } from '../src/auth/dto/user-auth.dto';
import { User } from '../src/user/schemas/user.schema';
import { SearchService } from '../src/search/search.service';
import { MentorService } from '../src/mentor/mentor.service';
import { ContentService } from '../src/content/content.service';
import { CreateContentDto } from '../src/content/dto/create-content.dto';
import { CreateTopicDto } from '../src/topic/dto/create-topic.dto';
import { CreateMentorDto } from '../src/mentor/dto/create-mentor.dto';
import { Category } from '../src/content/schemas/content.schema';

describe('Search Controller - (e2e)', () => {
  let app: INestApplication;
  let userService: UserService;
  let authService: AuthService;
  let topicService: TopicService;
  let mentorService: MentorService;
  let searchService: SearchService;
  let contentService: ContentService;

  let userAuthDto: UserAuthDto;
  let apiKey: ApiKey;
  let role: Role;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    userService = module.get(UserService);
    authService = module.get(AuthService);
    topicService = module.get(TopicService);
    mentorService = module.get(MentorService);
    searchService = module.get(SearchService);
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
    });

    await app.init();
  });

  afterEach(async () => {
    await authService.deleteApiKey(apiKey);
    await authService.deleteRole(role);
    await userService.delete(userAuthDto.user as User);
    await authService.signOutFromEverywhere(userAuthDto.user as User);
    await app.close();
  });

  it('should sent the topic when matched', async () => {
    const createTopicDto = new CreateTopicDto({
      name: 'topic_name',
      title: 'topic_title',
      description: 'topic_description',
      thumbnail: 'https://topic.com/thumbnail.png',
      coverImgUrl: 'https://topic.com/coverImgUrl.png',
      score: 0.1,
    });

    const topic = await topicService.create(
      userAuthDto.user as User,
      createTopicDto,
    );

    const searchDto = searchService.topicToSearchDto(topic);
    const data = { ...searchDto, id: searchDto.id.toHexString() };

    try {
      await request(app.getHttpServer())
        .get('/search?query=topi&filter=TOPIC_INFO')
        .set('Content-Type', 'application/json')
        .set('x-api-key', apiKey.key)
        .set('Authorization', `Bearer ${userAuthDto.tokens.accessToken}`)
        .expect(200)
        .expect((response) => {
          expect(response.body.statusCode).toEqual(StatusCode.SUCCESS);
          expect(response.body.data).not.toBeNull();
          expect(response.body.data).toContainEqual(data);
        });
    } finally {
      await topicService.deleteFromDb(topic);
    }
  });

  it('should sent the mentor when matched', async () => {
    const createMentorDto = new CreateMentorDto({
      name: 'mentor_name',
      occupation: 'mentor_occupation',
      title: 'mentor_title',
      description: 'mentor_description',
      thumbnail: 'https://mentor.com/thumbnail.png',
      coverImgUrl: 'https://mentor.com/coverImgUrl.png',
      score: 0.1,
    });

    const mentor = await mentorService.create(
      userAuthDto.user as User,
      createMentorDto,
    );

    const searchDto = searchService.mentorToSearchDto(mentor);
    const data = { ...searchDto, id: searchDto.id.toHexString() };

    try {
      await request(app.getHttpServer())
        .get('/search?query=mento&filter=MENTOR_INFO')
        .set('Content-Type', 'application/json')
        .set('x-api-key', apiKey.key)
        .set('Authorization', `Bearer ${userAuthDto.tokens.accessToken}`)
        .expect(200)
        .expect((response) => {
          expect(response.body.statusCode).toEqual(StatusCode.SUCCESS);
          expect(response.body.data).not.toBeNull();
          expect(response.body.data).toContainEqual(data);
        });
    } finally {
      await mentorService.deleteFromDb(mentor);
    }
  });

  it('should sent the content when matched', async () => {
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

    const content = await contentService.createContent(
      createContentDto,
      userAuthDto.user as User,
    );

    await contentService.publishContent(userAuthDto.user as User, content._id);

    const searchDto = searchService.contentToSearchDto(content);
    const data = { ...searchDto, id: searchDto.id.toHexString() };

    try {
      await request(app.getHttpServer())
        .get('/search?query=cont')
        .set('Content-Type', 'application/json')
        .set('x-api-key', apiKey.key)
        .set('Authorization', `Bearer ${userAuthDto.tokens.accessToken}`)
        .expect(200)
        .expect((response) => {
          expect(response.body.statusCode).toEqual(StatusCode.SUCCESS);
          expect(response.body.data).not.toBeNull();
          expect(response.body.data).toContainEqual(data);
        });
    } finally {
      await contentService.deleteFromDb(content);
    }
  });
});
