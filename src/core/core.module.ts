import { Module, ValidationPipe } from '@nestjs/common';
import { APP_FILTER, APP_INTERCEPTOR, APP_PIPE } from '@nestjs/core';
import { ResponseTransformer } from './interceptors/response.transformer';
import { ExpectionHandler } from './interceptors/exception.handler';
import { ResponseValidation } from './interceptors/response.validations';
import { ConfigModule } from '@nestjs/config';
import { WinstonLogger } from '../setup/winston.logger';
import { CoreController } from './core.controller';

@Module({
  imports: [ConfigModule],
  providers: [
    { provide: APP_INTERCEPTOR, useClass: ResponseTransformer },
    { provide: APP_INTERCEPTOR, useClass: ResponseValidation },
    { provide: APP_FILTER, useClass: ExpectionHandler },
    {
      provide: APP_PIPE,
      useValue: new ValidationPipe({
        transform: true,
        whitelist: true,
        forbidNonWhitelisted: true,
      }),
    },
    WinstonLogger,
  ],
  controllers: [CoreController],
})
export class CoreModule {}
