import { registerAs } from '@nestjs/config';

export const TokenConfigName = 'token';

export interface TokenConfig {
  accessTokenValidity: number;
  refreshTokenValidity: number;
  issuer: string;
  audience: string;
}

export default registerAs(TokenConfigName, () => ({
  accessTokenValidity: parseInt(process.env.ACCESS_TOKEN_VALIDITY_SEC || '0'),
  refreshTokenValidity: parseInt(process.env.REFRESH_TOKEN_VALIDITY_SEC || '0'),
  issuer: process.env.TOKEN_ISSUER || '',
  audience: process.env.TOKEN_AUDIENCE || '',
}));
