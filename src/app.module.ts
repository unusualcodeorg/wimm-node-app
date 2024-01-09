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

@Module({
  imports: [
    ConfigModule.forRoot({
      load: [
        serverConfig,
        databaseConfig,
        authkeyConfig,
        tokenConfig,
        diskConfig,
      ],
      cache: true,
    }),
    MongooseModule.forRootAsync({
      imports: [ConfigModule],
      useClass: DatabaseFactory,
    }),
    CoreModule,
    AuthModule,
    MessageModule,
    FilesModule,
    ScrapperModule,
  ],
  providers: [
    {
      provide: 'Logger',
      useClass: WinstonLogger,
    },
  ],
})
export class AppModule {}
