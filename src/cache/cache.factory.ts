import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { CacheConfig, CacheConfigName } from '../config/cache.config';
import { CacheModuleOptions, CacheOptionsFactory } from '@nestjs/cache-manager';
import { createKeyv } from '@keyv/redis';

@Injectable()
export class CacheConfigFactory implements CacheOptionsFactory {
  constructor(private readonly configService: ConfigService) {}

  async createCacheOptions(): Promise<CacheModuleOptions> {
    const cacheConfig =
      this.configService.getOrThrow<CacheConfig>(CacheConfigName);
    const redisURL = `redis://:${cacheConfig.password}@${cacheConfig.host}:${cacheConfig.port}`;
    const keyv = createKeyv(redisURL);
    return {
      stores: keyv,
    };
  }
}
