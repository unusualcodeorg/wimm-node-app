import { Injectable, Logger, UnauthorizedException } from '@nestjs/common';
import { TokenPayload } from './token/token.payload';
import { JwtService, TokenExpiredError } from '@nestjs/jwt';
import { UserService } from '../user/user.service';
import { InjectModel } from '@nestjs/mongoose';
import { Keystore } from './schemas/keystore.schema';
import { Model } from 'mongoose';
import { User } from '../user/schemas/user.schema';

@Injectable()
export class AuthService {
  constructor(
    @InjectModel(Keystore.name) private readonly keystoreModel: Model<Keystore>,
    private readonly jwtService: JwtService,
    private readonly userService: UserService,
  ) {}

  async findKeystore(client: User, key: string) {
    return this.keystoreModel
      .findOne({
        client: client._id,
        primaryKey: key,
        status: true,
      })
      .lean()
      .exec();
  }

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
