import { Body, Controller, HttpCode, HttpStatus, Post } from '@nestjs/common';
import { AuthService } from './auth.service';
import { Public } from './decorators/public.decorator';
import { SignInBasicDto } from './dto/signin-basic.dto';
import { Permissions } from '../core/decorators/permissions.decorator';
import { Permission } from '../core/schemas/apikey.schema';

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
}
