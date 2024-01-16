import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import * as request from 'supertest';
import { AppModule } from '../src/app.module';
import { Connection } from 'mongoose';
import { getConnectionToken } from '@nestjs/mongoose';
import { CacheService } from '../src/cache/cache.service';

describe('AppController (e2e)', () => {
  let app: INestApplication;
  let connection: Connection;
  let cacheService: CacheService;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    connection = await module.get(getConnectionToken());
    cacheService = module.get<CacheService>(CacheService);
    app = module.createNestApplication();
    await app.init();
  });

  afterEach(async () => {
    await cacheService.getStore().client.disconnect();
    await connection.close();
    await app.close();
  });

  it('/GET', () => {
    return request(app.getHttpServer())
      .get('/')
      .expect(404)
      .expect(/Cannot GET/);
  });
});
