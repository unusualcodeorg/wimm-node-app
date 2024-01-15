import { Module } from '@nestjs/common';
import { MongooseModule } from '@nestjs/mongoose';
import { ConfigModule } from '@nestjs/config';
import serverConfig from './config/server.config';
import { MessageModule } from './message/message.module';
import { DatabaseFactory } from './setup/database.factory';
import databaseConfig from './config/database.config';
import { CoreModule } from './core/core.module';
import authkeyConfig from './config/authkey.config';
import tokenConfig from './config/token.config';
import { AuthModule } from './auth/auth.module';
import diskConfig from './config/disk.config';
import { FilesModule } from './files/files.module';
import { WinstonLogger } from './setup/winston.logger';
import { ScrapperModule } from './scrapper/scrapper.module';
import { MentorModule } from './mentor/mentor.module';
import { TopicModule } from './topic/topic.module';
import { SubscriptionModule } from './subscription/subscription.module';
import { ContentModule } from './content/content.module';
import { BookmarkModule } from './bookmark/bookmark.module';
import { SearchModule } from './search/search.module';
import { RedisCacheModule } from './cache/redis-cache.module';
import cacheConfig from './config/cache.config';

@Module({
  imports: [
    ConfigModule.forRoot({
      load: [
        serverConfig,
        databaseConfig,
        cacheConfig,
        authkeyConfig,
        tokenConfig,
        diskConfig,
      ],
      cache: true,
      envFilePath: getEnvFilePath(),
    }),
    MongooseModule.forRootAsync({
      imports: [ConfigModule],
      useClass: DatabaseFactory,
    }),
    RedisCacheModule,
    CoreModule,
    AuthModule,
    MessageModule,
    FilesModule,
    ScrapperModule,
    MentorModule,
    TopicModule,
    SubscriptionModule,
    ContentModule,
    BookmarkModule,
    SearchModule,
  ],
  providers: [
    {
      provide: 'Logger',
      useClass: WinstonLogger,
    },
  ],
})
export class AppModule {}

function getEnvFilePath() {
  return process.env.NODE_ENV === 'test' ? '.env.test' : '.env';
}
