import { Request } from 'express';
import { User } from '../../user/schemas/user.schema';
import { ApiKey } from '../../core/schemas/apikey.schema';

declare interface PublicRequest extends Request {
  apiKey: ApiKey;
}

declare interface RoleRequest extends PublicRequest {
  currentRoleCodes: string[];
}

declare interface ProtectedRequest extends RoleRequest {
  user: User;
  accessToken: string;
  // keystore: Keystore;
}

declare interface Tokens {
  accessToken: string;
  refreshToken: string;
}
