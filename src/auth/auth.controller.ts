import {
  Body,
  Controller,
  Delete,
  HttpCode,
  HttpStatus,
  Post,
  Request,
  UnauthorizedException,
} from '@nestjs/common';
import { AuthService } from './auth.service';
import { Public } from './decorators/public.decorator';
import { SignInBasicDto } from './dto/signin-basic.dto';
import { Permissions } from '../core/decorators/permissions.decorator';
import { Permission } from '../core/schemas/apikey.schema';
import { ProtectedRequest } from '../core/http/request';
import { TokenRefreshDto } from './dto/token-refresh.dto';

@Permissions([Permission.GENERAL])
@Controller('auth')
export class AuthController {
  constructor(private authService: AuthService) {}

  @Public()
  @HttpCode(HttpStatus.OK)
  @Post('login/basic')
  async signIn(@Body() signInBasicDto: SignInBasicDto) {
    const { user, tokens } = await this.authService.signIn(signInBasicDto);
    return {
      user: {
        _id: user._id,
        name: user.name,
        email: user.email,
        profilePicUrl: user.profilePicUrl,
      },
      roles: user.roles.map((role) => ({ _id: role._id, code: role.code })),
      tokens: tokens,
    };
  }

  @Delete('logout')
  async signOut(@Request() request: ProtectedRequest) {
    await this.authService.signOut(request.keystore);
    return 'Logout sucess';
  }

  @Public()
  @Post('token/refresh')
  async tokenRefresh(
    @Request() request: ProtectedRequest,
    @Body() tokenRefreshDto: TokenRefreshDto,
  ) {
    const [type, token] = request.headers.authorization?.split(' ') ?? [];
    if (type !== 'Bearer' || token === undefined)
      throw new UnauthorizedException();

    const { tokens } = await this.authService.refreshToken(
      tokenRefreshDto,
      token,
    );
    return tokens;
  }
}
