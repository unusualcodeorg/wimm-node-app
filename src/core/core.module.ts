import { Module, ValidationPipe } from '@nestjs/common';
import { APP_FILTER, APP_GUARD, APP_INTERCEPTOR, APP_PIPE } from '@nestjs/core';
import { ResponseTransformer } from './interceptors/response.transformer';
import { CoreService } from './core.service';
import { MongooseModule } from '@nestjs/mongoose';
import { ApiKey, ApiKeySchema } from './schemas/apikey.schema';
import { ApiKeyGuard } from './guards/apikey.guard';
import { ExpectionHandler } from './interceptors/exception.handler';
import { ResponseValidation } from './interceptors/response.validations';
import { ConfigModule } from '@nestjs/config';
import { MongoIdTransformer } from './interceptors/mongoid.transformer';

@Module({
  imports: [
    MongooseModule.forFeature([{ name: ApiKey.name, schema: ApiKeySchema }]),
    ConfigModule,
  ],
  providers: [
    { provide: APP_INTERCEPTOR, useClass: ResponseTransformer },
    { provide: APP_INTERCEPTOR, useClass: ResponseValidation },
    { provide: APP_FILTER, useClass: ExpectionHandler },
    { provide: APP_GUARD, useClass: ApiKeyGuard },
    {
      provide: APP_PIPE,
      useClass: MongoIdTransformer,
    },
    {
      provide: APP_PIPE,
      useValue: new ValidationPipe({
        transform: true,
        whitelist: true,
        forbidNonWhitelisted: true,
      }),
    },
    CoreService,
  ],
})
export class CoreModule {}
