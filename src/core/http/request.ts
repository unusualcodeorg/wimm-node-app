import { Request } from 'express';
import { User } from '../../user/schemas/user.schema';
import { ApiKey } from '../schemas/apikey.schema';
import { Keystore } from '../../auth/schemas/keystore.schema';

export interface PublicRequest extends Request {
  apiKey: ApiKey;
}

export interface RoleRequest extends PublicRequest {
  currentRoleCodes: string[];
}

export interface ProtectedRequest extends RoleRequest {
  user: User;
  accessToken: string;
  keystore: Keystore;
}

export interface Tokens {
  accessToken: string;
  refreshToken: string;
}
