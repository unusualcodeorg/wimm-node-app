import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { Roles } from '../decorators/roles.decorator';
import { ProtectedRequest } from '../../core/http/request';

@Injectable()
export class RolesGuard implements CanActivate {
  constructor(private readonly reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const request = context.switchToHttp().getRequest<ProtectedRequest>();
    const user = request.user;

    if (!user) return true; // Note: if authenticated then authorization role in required

    let roles = this.reflector.get(Roles, context.getClass());
    if (!roles) roles = this.reflector.get(Roles, context.getHandler());
    if (!roles) throw new ForbiddenException('Permission Denied');

    const hasRole = () =>
      user.roles.some((role) => !!roles.find((item) => item === role.code));

    if (!hasRole()) throw new ForbiddenException('Permission Denied');
    return true;
  }
}
