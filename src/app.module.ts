import { Module } from '@nestjs/common';
import { MongooseModule } from '@nestjs/mongoose';
import { ConfigModule, ConfigService } from '@nestjs/config';
import serverConfig from './config/server.config';
import { MessageModule } from './message/message.module';
import { DatabaseFactory } from './core/database.factory';
import databaseConfig from './config/database.config';

@Module({
  imports: [
    ConfigModule.forRoot({
      load: [serverConfig, databaseConfig],
      cache: true,
    }),
    MongooseModule.forRootAsync({
      imports: [ConfigModule],
      useClass: DatabaseFactory,
      inject: [ConfigService],
    }),
    MessageModule,
  ],
})
export class AppModule {}
