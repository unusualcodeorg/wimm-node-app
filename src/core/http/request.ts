import { Request } from 'express';

export interface PublicRequest extends Request {
  apiKey?: any;
}

export interface RoleRequest extends PublicRequest {
  currentRoleCodes?: string[];
}

export interface ProtectedRequest extends RoleRequest {
  user?: any;
  accessToken?: string;
  keystore?: any;
}
