import { registerAs } from '@nestjs/config';
import {
  ACCESS_TOKEN_VALIDITY_SEC,
  REFRESH_TOKEN_VALIDITY_SEC,
  TOKEN_ISSUER,
  TOKEN_AUDIENCE,
} from '@/utils';

export const TokenConfigName = 'token';

export interface TokenConfig {
  accessTokenValidity: number;
  refreshTokenValidity: number;
  issuer: string;
  audience: string;
}

export default registerAs(TokenConfigName, () => ({
  accessTokenValidity: ACCESS_TOKEN_VALIDITY_SEC,
  refreshTokenValidity: REFRESH_TOKEN_VALIDITY_SEC,
  issuer: TOKEN_ISSUER,
  audience: TOKEN_AUDIENCE,
}));
