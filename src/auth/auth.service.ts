import {
  BadRequestException,
  Injectable,
  InternalServerErrorException,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';
import { TokenPayload } from './token/token.payload';
import { JwtService, TokenExpiredError } from '@nestjs/jwt';
import { UserService } from '../user/user.service';
import { InjectModel } from '@nestjs/mongoose';
import { Keystore } from './schemas/keystore.schema';
import { Model, Types } from 'mongoose';
import { User } from '../user/schemas/user.schema';
import { SignInBasicDto } from './dto/signin-basic.dto';
import { ConfigService } from '@nestjs/config';
import { TokenConfig, TokenConfigName } from '../config/token.config';
import { compare, hash } from 'bcrypt';
import { randomBytes } from 'crypto';
import { TokenRefreshDto } from './dto/token-refresh.dto';
import { UserTokensDto } from './dto/user-tokens.dto';
import { SignUpBasicDto } from './dto/signup-basic.dto';
import { Role, RoleCode } from './schemas/role.schema';
import { ApiKey } from './schemas/apikey.schema';

@Injectable()
export class AuthService {
  constructor(
    @InjectModel(ApiKey.name) private readonly apikeyModel: Model<ApiKey>,
    @InjectModel(Keystore.name) private readonly keystoreModel: Model<Keystore>,
    @InjectModel(Role.name) private readonly roleModel: Model<Role>,
    private readonly jwtService: JwtService,
    private readonly userService: UserService,
    private readonly configService: ConfigService,
  ) {}

  async signUpBasic(
    signUpBasicDto: SignUpBasicDto,
  ): Promise<{ user: User; tokens: UserTokensDto }> {
    const user = await this.userService.findByEmail(signUpBasicDto.email);
    if (user) throw new BadRequestException('User already exists');

    const role = await this.findRole(RoleCode.VIEWER);
    if (!role) throw new InternalServerErrorException();

    const password = await hash(signUpBasicDto.password, 5);

    const createdUser = await this.userService.create({
      ...signUpBasicDto,
      password: password,
      roles: [role],
      verified: false,
    });

    if (!createdUser) throw new InternalServerErrorException();

    const tokens = await this.createTokens(createdUser);

    return { user: createdUser, tokens: tokens };
  }

  async signInBasic(
    signInBasicDto: SignInBasicDto,
  ): Promise<{ user: User; tokens: UserTokensDto }> {
    const user = await this.userService.findByEmail(signInBasicDto.email);
    if (!user) throw new NotFoundException('User not found');
    if (!user.password)
      throw new BadRequestException('User credential not set');

    const match = await compare(signInBasicDto.password, user.password);
    if (!match) throw new UnauthorizedException('Authentication failure');

    const tokens = await this.createTokens(user);

    return { user: user, tokens: tokens };
  }

  async signOut(keystore: Keystore) {
    this.removeKeystore(keystore._id);
  }

  async signOutFromEverywhere(user: User) {
    return this.keystoreModel.deleteMany({ client: user }).lean().exec();
  }

  async refreshToken(
    tokenRefreshDto: TokenRefreshDto,
    accessToken: string,
  ): Promise<{ user: User; tokens: UserTokensDto }> {
    const accessTokenPayload = this.decodeToken(accessToken);
    const validAccessToken = this.validatePayload(accessTokenPayload);
    if (!validAccessToken)
      throw new UnauthorizedException('Invalid Access Token');

    const user = await this.userService.findUserById(
      new Types.ObjectId(accessTokenPayload.sub),
    );
    if (!user) throw new UnauthorizedException('User not registered');

    const refreshTokenPayload = await this.verifyToken(
      tokenRefreshDto.refreshToken,
    ).catch((e: Error) => {
      if (e instanceof TokenExpiredError)
        throw new UnauthorizedException('Refresh Token Expired');
      else throw new UnauthorizedException('Invalid Refresh Token');
    });

    const validRefreshToken = this.validatePayload(refreshTokenPayload);
    if (!validRefreshToken)
      throw new UnauthorizedException('Invalid Refresh Token');

    if (accessTokenPayload.sub !== refreshTokenPayload.sub)
      throw new UnauthorizedException('Invalid Access Token');

    const keystore = await this.findTokensKeystore(
      user,
      accessTokenPayload.prm,
      refreshTokenPayload.prm,
    );

    if (!keystore) throw new UnauthorizedException('Invalid access token');
    await this.removeKeystore(keystore._id);

    const tokens = await this.createTokens(user);

    return { user: user, tokens: tokens };
  }

  private async createTokens(user: User): Promise<UserTokensDto> {
    const tokenConfig =
      this.configService.getOrThrow<TokenConfig>(TokenConfigName);

    const accessTokenKey = randomBytes(64).toString('hex');
    const refreshTokenKey = randomBytes(64).toString('hex');

    await this.createKeystore(user, accessTokenKey, refreshTokenKey);

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

    return new UserTokensDto({
      accessToken: accessToken,
      refreshToken: refreshToken,
    });
  }

  validatePayload(payload: TokenPayload) {
    const tokenConfig =
      this.configService.getOrThrow<TokenConfig>(TokenConfigName);
    if (
      !payload ||
      !payload.iss ||
      !payload.sub ||
      !payload.aud ||
      !payload.prm ||
      payload.iss !== tokenConfig.issuer ||
      payload.aud !== tokenConfig.audience ||
      !Types.ObjectId.isValid(payload.sub)
    ) {
      return false;
    }
    return true;
  }

  private async createKeystore(
    client: User,
    primaryKey: string,
    secondaryKey: string,
  ) {
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

  private async findTokensKeystore(
    client: User,
    primaryKey: string,
    secondaryKey: string,
  ) {
    return this.keystoreModel
      .findOne({
        client: client,
        primaryKey: primaryKey,
        secondaryKey: secondaryKey,
        status: true,
      })
      .lean()
      .exec();
  }

  private async findRole(roleCode: RoleCode): Promise<Role | null> {
    return this.roleModel
      .findOne({
        code: roleCode,
        status: true,
      })
      .lean()
      .exec();
  }

  private async removeKeystore(id: Types.ObjectId) {
    return this.keystoreModel.findByIdAndDelete(id).lean().exec();
  }

  private async signToken(payload: TokenPayload) {
    return this.jwtService.signAsync({ ...payload });
  }

  async verifyToken(token: string) {
    try {
      return await this.jwtService.verifyAsync<TokenPayload>(token);
    } catch (error) {
      if (error instanceof TokenExpiredError) throw error;
      throw new UnauthorizedException('Invalid Access Token');
    }
  }

  private decodeToken(token: string) {
    return this.jwtService.decode<TokenPayload>(token);
  }

  async createRole(role: Omit<Role, '_id' | 'status'>): Promise<Role> {
    const created = await this.roleModel.create(role);
    return created.toObject();
  }

  async deleteRole(role: Role) {
    return this.roleModel.findByIdAndDelete(role._id).lean().exec();
  }

  async findApiKey(key: string): Promise<ApiKey | null> {
    return this.apikeyModel.findOne({ key: key, status: true }).lean().exec();
  }

  async createApiKey(apikey: Omit<ApiKey, '_id' | 'status'>): Promise<ApiKey> {
    const created = await this.apikeyModel.create(apikey);
    return created.toObject();
  }

  async deleteApiKey(apikey: ApiKey) {
    return this.apikeyModel.findByIdAndDelete(apikey._id).lean().exec();
  }
}
