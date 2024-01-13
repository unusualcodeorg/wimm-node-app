import { Test } from '@nestjs/testing';
import { AuthGuard } from './auth.guard';
import { Reflector } from '@nestjs/core';
import { ExecutionContext, UnauthorizedException } from '@nestjs/common';
import { AuthService } from '../auth.service';
import { UserService } from '../../user/user.service';
import { TokenPayload } from '../token/token.payload';
import { User } from '../../user/schemas/user.schema';
import { Keystore } from '../schemas/keystore.schema';
import { Types } from 'mongoose';
import { ProtectedRequest } from '../../core/http/request';

describe('AuthGuard', () => {
  let authGuard: AuthGuard;
  let isPublic = false;

  const signedInToken = 'signedInToken';
  const signOutToken = 'signOutToken';

  const signedInTokenPayload = {
    sub: new Types.ObjectId().toHexString(),
    prm: 'prm',
  } as TokenPayload;

  const signOutTokenPayload = {
    sub: new Types.ObjectId().toHexString(),
    prm: 'prm',
  } as TokenPayload;

  const user = {} as User;
  const signedOutUser = {} as User;

  const keystore = {} as Keystore;
  let request: ProtectedRequest;

  const authServiceMock = {
    verifyToken: jest.fn((token) => {
      if (token === signedInToken) return signedInTokenPayload;
      if (token === signOutToken) return signOutTokenPayload;
      throw new UnauthorizedException();
    }),
    validatePayload: jest.fn((payload) => {
      return (
        payload === signedInTokenPayload || payload === signOutTokenPayload
      );
    }),
    findKeystore: jest.fn((usr, prm) => {
      if (usr === user && prm === signedInTokenPayload.prm) return keystore;
      return null;
    }),
  };
  const userServiceMock = {
    findUserById: jest.fn((id: Types.ObjectId) => {
      if (id.toHexString() === signedInTokenPayload.sub) return user;
      if (id.toHexString() === signOutTokenPayload.sub) return signedOutUser;
      return null;
    }),
  };

  const reflectorMock = {
    getAllAndOverride: jest.fn(() => isPublic),
  };

  const getRequestMock = jest.fn(() => request);

  const context = {
    getHandler: () => ({}),
    getClass: () => ({}),
    switchToHttp: () => ({
      getRequest: () => getRequestMock(),
    }),
  } as ExecutionContext;

  beforeEach(async () => {
    jest.clearAllMocks();
    const module = await Test.createTestingModule({
      providers: [
        AuthGuard,
        { provide: Reflector, useValue: reflectorMock },
        { provide: AuthService, useValue: authServiceMock },
        { provide: UserService, useValue: userServiceMock },
      ],
    }).compile();

    authGuard = module.get(AuthGuard);
  });

  it('should pass for public api', async () => {
    isPublic = true;
    request = { headers: {} } as ProtectedRequest;
    const pass = authGuard.canActivate(context);
    expect(pass).resolves.toBe(true);
    expect(reflectorMock.getAllAndOverride).toHaveBeenCalled();
    expect(getRequestMock).not.toHaveBeenCalled();
  });

  it('should throw UnauthorizedException if auth token is not sent', async () => {
    isPublic = false;
    request = { headers: {} } as ProtectedRequest;
    const spyExtractTokenFromHeader = jest.spyOn(
      authGuard as any,
      'extractTokenFromHeader',
    );
    await expect(authGuard.canActivate(context)).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
    expect(reflectorMock.getAllAndOverride).toHaveBeenCalled();
    expect(getRequestMock).toHaveBeenCalled();
    expect(spyExtractTokenFromHeader).toHaveBeenCalledWith(request);
    expect(authServiceMock.verifyToken).not.toHaveBeenCalled();
  });

  it('should throw UnauthorizedException if invalid token is sent', async () => {
    isPublic = false;
    request = {
      headers: { authorization: 'Bearer wrongToken' },
    } as ProtectedRequest;
    await expect(authGuard.canActivate(context)).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
    expect(reflectorMock.getAllAndOverride).toHaveBeenCalled();
    expect(getRequestMock).toHaveBeenCalled();
    expect(authServiceMock.verifyToken).toHaveBeenCalledWith('wrongToken');
    expect(authServiceMock.validatePayload).not.toHaveBeenCalled();
  });

  it('should throw UnauthorizedException if signout user token is sent', async () => {
    isPublic = false;
    request = {
      headers: { authorization: 'Bearer ' + signOutToken },
    } as ProtectedRequest;

    await expect(authGuard.canActivate(context)).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
    expect(reflectorMock.getAllAndOverride).toHaveBeenCalled();
    expect(getRequestMock).toHaveBeenCalled();
    expect(authServiceMock.verifyToken).toHaveBeenCalledWith(signOutToken);
    expect(authServiceMock.validatePayload).toHaveBeenCalled();
    expect(userServiceMock.findUserById).toHaveBeenCalled();
    expect(authServiceMock.findKeystore).toHaveBeenCalled();
  });

  it('should return true if correct token is sent for logged in user', async () => {
    isPublic = false;
    request = {
      headers: { authorization: 'Bearer ' + signedInToken },
    } as ProtectedRequest;

    const pass = await authGuard.canActivate(context);
    expect(pass).toBe(true);
    expect(reflectorMock.getAllAndOverride).toHaveBeenCalled();
    expect(getRequestMock).toHaveBeenCalled();
    expect(authServiceMock.verifyToken).toHaveBeenCalledWith(signedInToken);
    expect(authServiceMock.validatePayload).toHaveBeenCalled();
    expect(userServiceMock.findUserById).toHaveBeenCalled();
    expect(authServiceMock.findKeystore).toHaveBeenCalled();
  });
});
