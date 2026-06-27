import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import serverConfig from './config/server.config';
import databaseConfig from './config/database.config';
import { CoreModule } from './core/core.module';
import authkeyConfig from './config/authkey.config';
import tokenConfig from './config/token.config';
import diskConfig from './config/disk.config';
import { FilesModule } from './files/files.module';
import { WinstonLogger } from './setup/winston.logger';
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
    RedisCacheModule,
    CoreModule,
    FilesModule,
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

