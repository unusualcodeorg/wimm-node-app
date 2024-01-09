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
import { SignInEntity } from './entities/sign-in.entity';
import { TokensEntity } from './entities/tokens.entity';

@Permissions([Permission.GENERAL])
@Controller('auth')
export class AuthController {
  constructor(private authService: AuthService) {}

  @Public()
  @HttpCode(HttpStatus.OK)
  @Post('login/basic')
  async signIn(@Body() signInBasicDto: SignInBasicDto): Promise<SignInEntity> {
    const { user, tokens } = await this.authService.signIn(signInBasicDto);
    return new SignInEntity(user, tokens);
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
  ): Promise<TokensEntity> {
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
