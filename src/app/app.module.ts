import { Module } from '@nestjs/common';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { MongooseModule } from '@nestjs/mongoose';
import { ConfigModule, ConfigService } from '@nestjs/config';
import serverConfig from '../config/server.config';
import databaseConfig, {
  DatabaseConfig,
  DatabaseConfigName,
} from '../config/database.config';

@Module({
  imports: [
    ConfigModule.forRoot({
      load: [serverConfig, databaseConfig],
      cache: true,
    }),
    MongooseModule.forRootAsync({
      imports: [ConfigModule],
      connectionName: 'mongo',
      useFactory: async function (config: ConfigService) {
        const dbConfig = config.getOrThrow<DatabaseConfig>(DatabaseConfigName);

        const { user, host, port, name, minPoolSize, maxPoolSize } = dbConfig;

        const password = encodeURIComponent(dbConfig.password);

        const uri = `mongodb://${user}:${password}@${host}:${port}/${name}`;

        return {
          uri: uri,
          autoIndex: true,
          minPoolSize: minPoolSize,
          maxPoolSize: maxPoolSize,
          connectTimeoutMS: 60000, // Give up initial connection after 10 seconds
          socketTimeoutMS: 45000, // Close sockets after 45 seconds of inactivity
        };
      },
      inject: [ConfigService],
    }),
  ],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}
