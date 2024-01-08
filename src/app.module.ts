import { Module } from '@nestjs/common';
import { MongooseModule } from '@nestjs/mongoose';
import { ConfigModule, ConfigService } from '@nestjs/config';
import serverConfig from './config/server.config';
import { MessageModule } from './message/message.module';
import { DatabaseFactory } from './database.factory';
import databaseConfig from './config/database.config';
import { CoreModule } from './core/core.module';
import authkeyConfig from './config/authkey.config';
import tokenConfig from './config/token.config';
import { AuthModule } from './auth/auth.module';

@Module({
  imports: [
    ConfigModule.forRoot({
      load: [serverConfig, databaseConfig, authkeyConfig, tokenConfig],
      cache: true,
    }),
    MongooseModule.forRootAsync({
      imports: [ConfigModule],
      useClass: DatabaseFactory,
    }),
    CoreModule,
    AuthModule,
    MessageModule,
  ],
})
export class AppModule {}
