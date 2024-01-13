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

  const reflectorGetMock = jest.fn();
  const requestMock = jest.fn();

  const context = {
    getHandler: () => ({}),
    getClass: () => ({}),
    switchToHttp: () => ({
      getRequest: () => requestMock(),
    }),
  } as ExecutionContext;

  beforeEach(async () => {
    jest.clearAllMocks();
    const module = await Test.createTestingModule({
      providers: [
        RolesGuard,
        {
          provide: Reflector,
          useValue: {
            get: reflectorGetMock,
          },
        },
      ],
    }).compile();

    roleGuard = module.get(RolesGuard);
  });

  it('should pass if role is not provided', async () => {
    reflectorGetMock.mockReturnValue(null);
    const pass = await roleGuard.canActivate(context);
    expect(pass).toBe(true);
    expect(reflectorGetMock).toHaveBeenCalledTimes(2);
    expect(requestMock).not.toHaveBeenCalled();
  });

  it('should throw ForbiddenException if user is null', async () => {
    reflectorGetMock.mockReturnValue([RoleCode.VIEWER]);
    requestMock.mockReturnValue({ user: null });
    await expect(roleGuard.canActivate(context)).rejects.toBeInstanceOf(
      ForbiddenException,
    );
    expect(reflectorGetMock).toHaveBeenCalled();
    expect(requestMock).toHaveBeenCalledTimes(1);
  });

  it('should throw ForbiddenException if user does not have no role', async () => {
    requestMock.mockReturnValue({ user: user });
    reflectorGetMock.mockReturnValue([RoleCode.VIEWER]);
    await expect(roleGuard.canActivate(context)).rejects.toBeInstanceOf(
      ForbiddenException,
    );
    expect(reflectorGetMock).toHaveBeenCalled();
    expect(requestMock).toHaveBeenCalledTimes(1);
  });

  it('should throw ForbiddenException if user does not have allowed role', async () => {
    requestMock.mockReturnValue({ user: viewer });
    reflectorGetMock.mockReturnValue([RoleCode.ADMIN]);
    await expect(roleGuard.canActivate(context)).rejects.toBeInstanceOf(
      ForbiddenException,
    );
    expect(reflectorGetMock).toHaveBeenCalled();
    expect(requestMock).toHaveBeenCalledTimes(1);
  });

  it('should pass if user has allowed role', async () => {
    requestMock.mockReturnValue({ user: viewer });
    reflectorGetMock.mockReturnValue([RoleCode.VIEWER]);
    const pass = await roleGuard.canActivate(context);
    expect(pass).toBe(true);
    expect(reflectorGetMock).toHaveBeenCalled();
    expect(requestMock).toHaveBeenCalledTimes(1);
  });
});
