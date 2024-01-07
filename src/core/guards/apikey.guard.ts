import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
} from '@nestjs/common';
import { HeaderName } from '../../common/header';
import { CoreService } from '../core.service';

@Injectable()
export class ApiKeyGuard implements CanActivate {
  constructor(private readonly coreService: CoreService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest();

    const key = request.headers[HeaderName.API_KEY]?.toString();
    if (!key) throw new ForbiddenException();

    const apiKey = await this.coreService.findByKey(key);
    if (!apiKey) throw new ForbiddenException();

    // const user = request.user;
    // const hasRole = () =>
    //   user.roles.some((role) => !!roles.find((item) => item === role));

    // return user && user.roles && hasRole();
    return true;
  }
}
