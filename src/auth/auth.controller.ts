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
import { ProtectedRequest } from '../core/http/request';
import { TokenRefreshDto } from './dto/token-refresh.dto';
import { UserAuthDto } from './dto/user-auth.dto';
import { UserTokensDto } from './dto/user-tokens.dto';

@Controller('auth')
export class AuthController {
  constructor(private authService: AuthService) {}

  @Public()
  @HttpCode(HttpStatus.OK)
  @Post('login/basic')
  async signIn(@Body() signInBasicDto: SignInBasicDto): Promise<UserAuthDto> {
    const { user, tokens } = await this.authService.signIn(signInBasicDto);
    return new UserAuthDto(user, tokens);
  }

  @Delete('logout')
  async signOut(@Request() request: ProtectedRequest): Promise<string> {
    await this.authService.signOut(request.keystore);
    return 'Logout sucess';
  }

  @Public()
  @Post('token/refresh')
  async tokenRefresh(
    @Request() request: ProtectedRequest,
    @Body() tokenRefreshDto: TokenRefreshDto,
  ): Promise<UserTokensDto> {
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
