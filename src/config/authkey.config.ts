import { registerAs } from '@nestjs/config';

export const AuthKeyConfigName = 'authkey';

export interface AuthKeyConfig {
  publicKeyPath: string;
  privateKeyPath: string;
}

export default registerAs(AuthKeyConfigName, () => ({
  publicKeyPath: process.env.AUTH_PUBLIC_KEY_PATH,
  privateKeyPath: process.env.AUTH_PRIVATE_KEY_PATH,
}));
