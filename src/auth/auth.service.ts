import {
  BadRequestException,
  Injectable,
  InternalServerErrorException,
  Logger,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';
import { TokenPayload } from './token/token.payload';
import { JwtService, TokenExpiredError } from '@nestjs/jwt';
import { UserService } from '../user/user.service';
import { InjectModel } from '@nestjs/mongoose';
import { Keystore } from './schemas/keystore.schema';
import { Model } from 'mongoose';
import { User } from '../user/schemas/user.schema';
import { SignInBasicDto } from './dto/signin-basic.dto';
import { ConfigService } from '@nestjs/config';
import { TokenConfig, TokenConfigName } from '../config/token.config';
import { compare } from 'bcrypt';
import { randomBytes } from 'crypto';

@Injectable()
export class AuthService {
  constructor(
    @InjectModel(Keystore.name) private readonly keystoreModel: Model<Keystore>,
    private readonly jwtService: JwtService,
    private readonly userService: UserService,
    private readonly configService: ConfigService,
  ) {}

  async signIn(signInBasicDto: SignInBasicDto) {
    const user = await this.userService.findByEmail(signInBasicDto.email);
    if (!user) throw new NotFoundException('User not found');
    if (!user.password)
      throw new BadRequestException('User credential not set');

    const match = await compare(signInBasicDto.password, user.password);
    if (!match) throw new UnauthorizedException('Authentication failure');

    const accessTokenKeyId = randomBytes(64).toString('hex');
    const refreshTokenKeyId = randomBytes(64).toString('hex');

    await this.createKeystore(user, accessTokenKeyId, refreshTokenKeyId);

    const tokens = await this.createTokens(
      user,
      accessTokenKeyId,
      refreshTokenKeyId,
    );

    return { user: user, tokens: tokens };
  }

  private async createTokens(
    user: User,
    accessTokenKey: string,
    refreshTokenKey: string,
  ): Promise<{ accessToken: string; refreshToken: string }> {
    const tokenConfig =
      this.configService.getOrThrow<TokenConfig>(TokenConfigName);

    const accessTokenPayload = new TokenPayload(
      tokenConfig.issuer,
      tokenConfig.audience,
      user._id.toString(),
      accessTokenKey,
      tokenConfig.accessTokenValidity,
    );

    const refreshTokenPayload = new TokenPayload(
      tokenConfig.issuer,
      tokenConfig.audience,
      user._id.toString(),
      refreshTokenKey,
      tokenConfig.refreshTokenValidity,
    );

    const accessToken = await this.signToken(accessTokenPayload);
    if (!accessToken) throw new InternalServerErrorException();

    const refreshToken = await this.signToken(refreshTokenPayload);
    if (!refreshToken) throw new InternalServerErrorException();

    return {
      accessToken: accessToken,
      refreshToken: refreshToken,
    };
  }

  private async createKeystore(
    client: User,
    primaryKey: string,
    secondaryKey: string,
  ): Promise<Keystore> {
    const keystore = await this.keystoreModel.create({
      client: client,
      primaryKey: primaryKey,
      secondaryKey: secondaryKey,
    });
    return keystore.toObject();
  }

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

  private async signToken(payload: TokenPayload): Promise<string> {
    return this.jwtService.signAsync({ ...payload });
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

  private decodeToken(token: string): TokenPayload {
    return this.jwtService.decode<TokenPayload>(token);
  }
}
