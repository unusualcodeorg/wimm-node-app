import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { Request } from 'express';
import { IS_PUBLIC_KEY } from '../decorators/public.decorator';
import { ProtectedRequest } from '../../core/http/request';
import { TokenPayload } from '../token/token.payload';
import { TokenConfig, TokenConfigName } from '../../config/token.config';
import { Types } from 'mongoose';
import { ConfigService } from '@nestjs/config';
import { AuthService } from '../auth.service';
import { UserService } from '../../user/user.service';

@Injectable()
export class AuthGuard implements CanActivate {
  constructor(
    private readonly configService: ConfigService,
    private readonly authService: AuthService,
    private readonly reflector: Reflector,
    private readonly userService: UserService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (isPublic) return true;

    const request = context.switchToHttp().getRequest<ProtectedRequest>();
    const token = this.extractTokenFromHeader(request);
    if (!token) throw new UnauthorizedException();

    const payload = await this.authService.verifyToken(token);
    const tokenConfig =
      this.configService.getOrThrow<TokenConfig>(TokenConfigName);

    this.validatePayload(payload, tokenConfig);

    const user = await this.userService.findUserById(
      new Types.ObjectId(payload.sub),
    );
    if (!user) throw new UnauthorizedException('User not registered');

    const keystore = await this.authService.findKeystore(user, payload.prm);
    if (!keystore) throw new UnauthorizedException('Invalid access token');

    request.user = user;
    request.keystore = keystore;

    return true;
  }

  private extractTokenFromHeader(request: Request): string | undefined {
    const [type, token] = request.headers.authorization?.split(' ') ?? [];
    return type === 'Bearer' ? token : undefined;
  }

  private validatePayload = (
    payload: TokenPayload,
    tokenConfig: TokenConfig,
  ): boolean => {
    if (
      !payload ||
      !payload.iss ||
      !payload.sub ||
      !payload.aud ||
      !payload.prm ||
      payload.iss !== tokenConfig.issuer ||
      payload.aud !== tokenConfig.audience ||
      !Types.ObjectId.isValid(payload.sub)
    )
      throw new UnauthorizedException('Invalid Access Token');
    return true;
  };
}
