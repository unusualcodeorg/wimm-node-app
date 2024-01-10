import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
} from '@nestjs/common';
import { HeaderName } from '../http/header';
import { CoreService } from '../core.service';
import { Reflector } from '@nestjs/core';
import { Permissions } from '../decorators/permissions.decorator';
import { PublicRequest } from '../http/request';
import { Permission } from '../schemas/apikey.schema';

@Injectable()
export class ApiKeyGuard implements CanActivate {
  constructor(
    private readonly coreService: CoreService,
    private readonly reflector: Reflector,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const permissions = this.reflector.get(Permissions, context.getClass()) ?? [
      Permission.GENERAL,
    ];
    if (!permissions) throw new ForbiddenException();

    const request = context.switchToHttp().getRequest<PublicRequest>();

    const key = request.headers[HeaderName.API_KEY]?.toString();
    if (!key) throw new ForbiddenException();

    const apiKey = await this.coreService.findApiKey(key);
    if (!apiKey) throw new ForbiddenException();

    request.apiKey = apiKey;

    for (const askedPermission of permissions) {
      for (const allowedPemission of apiKey.permissions) {
        if (allowedPemission === askedPermission) return true;
      }
    }

    throw new ForbiddenException();
  }
}
