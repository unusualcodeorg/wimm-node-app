import { registerAs } from '@nestjs/config';
import { AUTH_PRIVATE_KEY_PATH, AUTH_PUBLIC_KEY_PATH } from '@/utils';

export const AuthKeyConfigName = 'authkey';

export interface AuthKeyConfig {
  publicKeyPath: string;
  privateKeyPath: string;
}

export default registerAs(AuthKeyConfigName, () => ({
  publicKeyPath: AUTH_PUBLIC_KEY_PATH,
  privateKeyPath: AUTH_PRIVATE_KEY_PATH,
}));
