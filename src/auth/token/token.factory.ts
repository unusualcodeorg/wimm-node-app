import { Injectable } from '@nestjs/common';
import { JwtOptionsFactory, JwtModuleOptions } from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';
import { AuthKeyConfig, AuthKeyConfigName } from '../../config/authkey.config';
import { readFile } from 'fs/promises';
import { join } from 'path';

@Injectable()
export class TokenFactory implements JwtOptionsFactory {
  constructor(private readonly configService: ConfigService) {}

  async createJwtOptions(): Promise<JwtModuleOptions> {
    const keys =
      this.configService.getOrThrow<AuthKeyConfig>(AuthKeyConfigName);

    const publicKey = await readFile(
      join(__dirname, '../../../', keys.publicKeyPath),
      'utf8',
    );
    const privateKey = await readFile(
      join(__dirname, '../../../', keys.privateKeyPath),
      'utf8',
    );

    return {
      publicKey,
      privateKey,
      signOptions: {
        algorithm: 'RS256',
      },
    };
  }
}
