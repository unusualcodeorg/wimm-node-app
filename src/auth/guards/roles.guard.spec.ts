import { Test } from '@nestjs/testing';
import { RolesGuard } from './roles.guard';
import { Reflector } from '@nestjs/core';
import { User } from '../../user/schemas/user.schema';
import { ExecutionContext, ForbiddenException } from '@nestjs/common';
import { Role, RoleCode } from '../schemas/role.schema';

describe('RoleGuard', () => {
  let roleGuard: RolesGuard;

  const user = { roles: [] as Role[] } as User;
  const viewer = { roles: [{ code: RoleCode.VIEWER } as Role] } as User;

  let currentUser: User | null = null;
  let currentRoleCode: RoleCode | null = null;

  const reflectorMock = {
    get: jest.fn(() => {
      if (!currentRoleCode) return null;
      return [currentRoleCode];
    }),
  };

  const requestMock = jest.fn(() => ({
    user: currentUser,
  }));

  const context = {
    getHandler: () => ({}),
    getClass: () => ({}),
    switchToHttp: () => ({
      getRequest: () => requestMock(),
    }),
  } as ExecutionContext;

  beforeEach(async () => {
    jest.clearAllMocks();
    requestMock.mockClear();
    const module = await Test.createTestingModule({
      providers: [RolesGuard, { provide: Reflector, useValue: reflectorMock }],
    }).compile();

    roleGuard = module.get(RolesGuard);
  });

  it('should pass if role is not provided', async () => {
    const pass = roleGuard.canActivate(context);
    expect(pass).resolves.toBe(true);
    expect(reflectorMock.get).toHaveBeenCalledTimes(2);
    expect(requestMock).not.toHaveBeenCalled();
  });

  it('should throw ForbiddenException if user is null', async () => {
    currentUser = null;
    currentRoleCode = RoleCode.VIEWER;
    roleGuard
      .canActivate(context)
      .catch((e) => expect(e).toBeInstanceOf(ForbiddenException));
    expect(reflectorMock.get).toHaveBeenCalled();
    expect(requestMock).toHaveBeenCalledTimes(1);
  });

  it('should throw ForbiddenException if user does not have no role', async () => {
    currentUser = user;
    currentRoleCode = RoleCode.VIEWER;
    roleGuard
      .canActivate(context)
      .catch((e) => expect(e).toBeInstanceOf(ForbiddenException));
    expect(reflectorMock.get).toHaveBeenCalled();
    expect(requestMock).toHaveBeenCalledTimes(1);
  });

  it('should throw ForbiddenException if user does not have allowed role', async () => {
    currentUser = viewer;
    currentRoleCode = RoleCode.ADMIN;
    roleGuard
      .canActivate(context)
      .catch((e) => expect(e).toBeInstanceOf(ForbiddenException));
    expect(reflectorMock.get).toHaveBeenCalled();
    expect(requestMock).toHaveBeenCalledTimes(1);
  });

  it('should pass if user has allowed role', async () => {
    currentUser = viewer;
    currentRoleCode = RoleCode.VIEWER;
    const pass = roleGuard.canActivate(context);

    expect(pass).resolves.toBe(true);
    expect(reflectorMock.get).toHaveBeenCalled();
    expect(requestMock).toHaveBeenCalledTimes(1);
  });
});
