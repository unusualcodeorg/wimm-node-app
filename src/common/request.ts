import { Request } from 'express';
import { User } from '../user/schemas/user.schema';
import { ApiKey } from '../core/schemas/apikey.schema';

export interface PublicRequest extends Request {
  apiKey: ApiKey;
}

export interface RoleRequest extends PublicRequest {
  currentRoleCodes: string[];
}

export interface ProtectedRequest extends RoleRequest {
  user: User;
  accessToken: string;
  // keystore: Keystore;
}

export interface Tokens {
  accessToken: string;
  refreshToken: string;
}
