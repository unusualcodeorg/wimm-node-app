import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import * as request from 'supertest';
import { AppModule } from '../src/app.module';
import { StatusCode } from '../src/core/http/response';
import { Permission } from '../src/core/schemas/apikey.schema';
import { CoreService } from '../src/core/core.service';

describe('AppController - API KEY (e2e)', () => {
  let app: INestApplication;
  let coreService: CoreService;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    coreService = module.get(CoreService);
    app = module.createNestApplication();

    await app.init();
  });

  afterEach(async () => {
    await app.close();
  });

  it('should throw 403 when x-api-key is not provided', () => {
    return request(app.getHttpServer())
      .get('/mentors/latest')
      .expect(403)
      .expect((response) => {
        expect(response.body.statusCode).toEqual(StatusCode.FAILURE);
        expect(response.body.message).toEqual('Forbidden');
      });
  });

  it('should throw 403 when wrong x-api-key is provided', async () => {
    const apiKey = await coreService.createApiKey({
      key: 'test_api_key',
      version: 1,
      permissions: [Permission.GENERAL],
      comments: ['For testing'],
    });

    try {
      await request(app.getHttpServer())
        .get('/mentors/latest')
        .set('Content-Type', 'application/json')
        .set('x-api-key', 'wrong_api_key')
        .expect(403)
        .expect((response) => {
          expect(response.body.statusCode).toEqual(StatusCode.FAILURE);
          expect(response.body.message).toEqual('Forbidden');
        });
    } finally {
      await coreService.deleteApiKey(apiKey);
    }
  });

  it('should throw 403 when x-api-key does not have right permissions', async () => {
    const apiKey = await coreService.createApiKey({
      key: 'test_api_key_1',
      version: 1,
      permissions: [Permission.XYZ_SERVICE],
      comments: ['For testing'],
    });

    try {
      await request(app.getHttpServer())
        .get('/mentors/latest')
        .set('Content-Type', 'application/json')
        .set('x-api-key', apiKey.key)
        .expect(403)
        .expect((response) => {
          expect(response.body.statusCode).toEqual(StatusCode.FAILURE);
          expect(response.body.message).toEqual('Forbidden');
        });
    } finally {
      await coreService.deleteApiKey(apiKey);
    }
  });

  it('should throw 401 when correct x-api-key is provided', async () => {
    const apiKey = await coreService.createApiKey({
      key: 'test_api_key_2',
      version: 1,
      permissions: [Permission.GENERAL],
      comments: ['For testing'],
    });

    try {
      await request(app.getHttpServer())
        .get('/mentors/latest')
        .set('Content-Type', 'application/json')
        .set('x-api-key', apiKey.key)
        .expect(401)
        .expect((response) => {
          expect(response.body.statusCode).toEqual(StatusCode.FAILURE);
          expect(response.body.message).toEqual('Unauthorized');
        });
    } finally {
      await coreService.deleteApiKey(apiKey);
    }
  });
});
