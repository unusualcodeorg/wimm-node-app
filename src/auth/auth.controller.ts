import { Body, Controller, HttpCode, HttpStatus, Post } from '@nestjs/common';
import { AuthService } from './auth.service';
import { Public } from './decorators/public.decorator';

@Controller('auth')
export class AuthController {
  constructor(private authService: AuthService) {}

  @Public()
  @HttpCode(HttpStatus.OK)
  @Post('login')
  signIn(@Body() signInDto: Record<string, any>) {
    // return this.authService.signIn(signInDto.username, signInDto.password);
    return signInDto;
  }

  // @Get('profile')
  // getProfile(@Request() req) {
  //   return req.user;
  // }
}
