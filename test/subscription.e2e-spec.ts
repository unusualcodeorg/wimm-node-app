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
import { MentorService } from '../src/mentor/mentor.service';
import { CreateTopicDto } from '../src/topic/dto/create-topic.dto';
import { CreateMentorDto } from '../src/mentor/dto/create-mentor.dto';
import { SubscriptionService } from '../src/subscription/subscription.service';
import { Topic } from '../src/topic/schemas/topic.schema';
import { Mentor } from '../src/mentor/schemas/mentor.schema';
import { SubscriptionDto } from '../src/subscription/dto/subscription.dto';

describe('Subscription Controller - (e2e)', () => {
  let app: INestApplication;
  let userService: UserService;
  let authService: AuthService;
  let topicService: TopicService;
  let mentorService: MentorService;
  let subscriptionService: SubscriptionService;

  let userAuthDto: UserAuthDto;
  let apiKey: ApiKey;
  let role: Role;
  let topic: Topic;
  let mentor: Mentor;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    userService = module.get(UserService);
    authService = module.get(AuthService);
    topicService = module.get(TopicService);
    mentorService = module.get(MentorService);
    subscriptionService = module.get(SubscriptionService);

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

    const createTopicDto = new CreateTopicDto({
      name: 'topic_name',
      title: 'topic_title',
      description: 'topic_description',
      thumbnail: 'https://topic.com/thumbnail.png',
      coverImgUrl: 'https://topic.com/coverImgUrl.png',
      score: 0.1,
    });

    topic = await topicService.create(userAuthDto.user as User, createTopicDto);

    const createMentorDto = new CreateMentorDto({
      name: 'mentor_name',
      occupation: 'mentor_occupation',
      title: 'mentor_title',
      description: 'mentor_description',
      thumbnail: 'https://mentor.com/thumbnail.png',
      coverImgUrl: 'https://mentor.com/coverImgUrl.png',
      score: 0.1,
    });

    mentor = await mentorService.create(
      userAuthDto.user as User,
      createMentorDto,
    );

    await app.init();
  });

  afterEach(async () => {
    await authService.deleteApiKey(apiKey);
    await authService.deleteRole(role);
    await userService.delete(userAuthDto.user as User);
    await topicService.deleteFromDb(topic);
    await mentorService.deleteFromDb(mentor);
    await subscriptionService.deleteUserSubscription(userAuthDto.user as User);
    await authService.signOutFromEverywhere(userAuthDto.user as User);
    await app.close();
  });

  it('should follow mentor and topic successfully', async () => {
    const subscriptionDto = new SubscriptionDto({
      mentorIds: [mentor._id],
      topicIds: [topic._id],
    });

    await request(app.getHttpServer())
      .post('/subscription/subscribe')
      .set('Content-Type', 'application/json')
      .set('x-api-key', apiKey.key)
      .set('Authorization', `Bearer ${userAuthDto.tokens.accessToken}`)
      .send(subscriptionDto)
      .expect(201)
      .expect(async (response) => {
        expect(response.body.statusCode).toEqual(StatusCode.SUCCESS);
        expect(response.body.message).toEqual('Followed Successfully');
      });
  });
});
