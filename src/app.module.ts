import { Module } from '@nestjs/common';
import { MongooseModule } from '@nestjs/mongoose';
import { ConfigModule } from '@nestjs/config';
import serverConfig from './config/server.config';
import { MessageModule } from './message/message.module';
import { DatabaseConfigService } from './config/database.config.service';
import databaseConfig from './config/database.config';

@Module({
  imports: [
    ConfigModule.forRoot({
      load: [serverConfig, databaseConfig],
      cache: true,
      isGlobal: true,
    }),
    MongooseModule.forRootAsync({
      useClass: DatabaseConfigService,
    }),
    MessageModule,
  ],
})
export class AppModule {}
