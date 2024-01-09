import { Injectable, Logger } from '@nestjs/common';
import {
  MongooseOptionsFactory,
  MongooseModuleOptions,
} from '@nestjs/mongoose';
import { ConfigService } from '@nestjs/config';
import { DatabaseConfig, DatabaseConfigName } from '../config/database.config';
import mongoose from 'mongoose';
import { ServerConfig, ServerConfigName } from '../config/server.config';

@Injectable()
export class DatabaseFactory implements MongooseOptionsFactory {
  constructor(private readonly configService: ConfigService) {}

  createMongooseOptions(): MongooseModuleOptions {
    const dbConfig =
      this.configService.getOrThrow<DatabaseConfig>(DatabaseConfigName);

    const { user, host, port, name, minPoolSize, maxPoolSize } = dbConfig;

    const password = encodeURIComponent(dbConfig.password);

    const uri = `mongodb://${user}:${password}@${host}:${port}/${name}`;

    const serverConfig =
      this.configService.getOrThrow<ServerConfig>(ServerConfigName);
    if (serverConfig.nodeEnv == 'development') mongoose.set({ debug: true });

    Logger.debug('Database URI:' + uri);

    return {
      uri: uri,
      autoIndex: true,
      minPoolSize: minPoolSize,
      maxPoolSize: maxPoolSize,
      connectTimeoutMS: 60000, // Give up initial connection after 10 seconds
      socketTimeoutMS: 45000, // Close sockets after 45 seconds of inactivity,
    };
  }
}
