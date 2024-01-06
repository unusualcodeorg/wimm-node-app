import { Inject, Injectable, Logger } from '@nestjs/common';
import {
  MongooseOptionsFactory,
  MongooseModuleOptions,
} from '@nestjs/mongoose';
import databaseConfig, { DatabaseConfig } from './database.config';

@Injectable()
export class DatabaseConfigService implements MongooseOptionsFactory {
  constructor(
    @Inject(databaseConfig.KEY)
    private config: DatabaseConfig,
  ) {}

  createMongooseOptions(): MongooseModuleOptions {
    const { user, host, port, name, minPoolSize, maxPoolSize } = this.config;

    const password = encodeURIComponent(this.config.password);

    const uri = `mongodb://${user}:${password}@${host}:${port}/${name}`;

    Logger.debug('Database URI:' + uri);

    return {
      uri: uri,
      autoIndex: true,
      minPoolSize: minPoolSize,
      maxPoolSize: maxPoolSize,
      connectTimeoutMS: 60000, // Give up initial connection after 10 seconds
      socketTimeoutMS: 45000, // Close sockets after 45 seconds of inactivity
    };
  }
}
