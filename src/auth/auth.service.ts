import { ConfigService } from '@nestjs/config';
import { Injectable, Logger, UnauthorizedException } from '@nestjs/common';
import { TokenPayload } from './token/token.payload';
import { JwtService, TokenExpiredError } from '@nestjs/jwt';

@Injectable()
export class AuthService {
  constructor(
    private readonly configService: ConfigService,
    private readonly jwtService: JwtService,
    // private readonly usersService: UsersService,
  ) {}

  // async signIn(username: string, pass: string) {
  //   const user = await this.usersService.findOne(username);
  //   if (user?.password !== pass) {
  //     throw new UnauthorizedException();
  //   }
  //   const payload = { username: user.username, sub: user.userId };
  //   return {
  //     access_token: await this.jwtService.signAsync(payload),
  //   };
  // }

  async signToken(payload: TokenPayload): Promise<string> {
    return this.jwtService.signAsync(payload);
  }

  async verifyToken(token: string): Promise<TokenPayload> {
    try {
      return await this.jwtService.verifyAsync<TokenPayload>(token);
    } catch (error) {
      Logger.error(error);
      if (error instanceof TokenExpiredError) throw error;
      throw new UnauthorizedException('Invalid Access Token');
    }
  }

  decodeToken(token: string): TokenPayload {
    return this.jwtService.decode<TokenPayload>(token);
  }
}
