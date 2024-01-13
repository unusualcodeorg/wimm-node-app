import { Test, TestingModule } from '@nestjs/testing';
import { ApiKeyGuard } from './apikey.guard';
import { CoreService } from '../core.service';
import { Reflector } from '@nestjs/core';
import { ExecutionContext, ForbiddenException } from '@nestjs/common';
import { HeaderName } from '../http/header';
import { ApiKey, Permission } from '../schemas/apikey.schema';

describe('ApiKeyGuard', () => {
  let apiKeyGuard: ApiKeyGuard;

  const generalKey = 'general';
  const serviceKey = 'service';

  let currentPermission: Permission | null = null;

  const generalApikey = {
    key: generalKey,
    permissions: [Permission.GENERAL],
  } as ApiKey;

  const serviceApikey = {
    key: serviceKey,
    permissions: [Permission.XYZ_SERVICE],
  } as ApiKey;

  const coreServiceMock = {
    findApiKey: jest.fn((key) => {
      switch (key) {
        case generalKey:
          return generalApikey;
        case serviceKey:
          return serviceApikey;
        default:
          return null;
      }
    }),
  };
  const reflectorMock = {
    get: jest.fn(() => {
      if (currentPermission) return [currentPermission];
      return null;
    }),
  };

  beforeEach(async () => {
    jest.clearAllMocks();
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        ApiKeyGuard,
        { provide: CoreService, useValue: coreServiceMock },
        { provide: Reflector, useValue: reflectorMock },
      ],
    }).compile();

    apiKeyGuard = module.get(ApiKeyGuard);
  });

  it('should throw ForbiddenException if API key is not sent', async () => {
    await expect(
      apiKeyGuard.canActivate(getExecutionContext()),
    ).rejects.toBeInstanceOf(ForbiddenException);

    expect(reflectorMock.get).toHaveBeenCalledTimes(1);
    expect(coreServiceMock.findApiKey).not.toHaveBeenCalled();
  });

  it('should throw ForbiddenException if wrong API key is sent', async () => {
    const currentKey = 'wrong';
    await expect(
      apiKeyGuard.canActivate(getExecutionContext(currentKey)),
    ).rejects.toBeInstanceOf(ForbiddenException);

    expect(reflectorMock.get).toHaveBeenCalledTimes(1);
    expect(coreServiceMock.findApiKey).toHaveBeenCalled();
  });

  it('should throw ForbiddenException if API key does not have permission', async () => {
    currentPermission = Permission.GENERAL;
    await expect(
      apiKeyGuard.canActivate(getExecutionContext(serviceKey)),
    ).rejects.toBeInstanceOf(ForbiddenException);

    expect(reflectorMock.get).toHaveBeenCalledTimes(1);
    expect(coreServiceMock.findApiKey).toHaveBeenCalled();
  });

  it('should pass if API key has general permission', async () => {
    currentPermission = Permission.GENERAL;
    const pass = await apiKeyGuard.canActivate(getExecutionContext(generalKey));

    expect(pass).toBe(true);
    expect(reflectorMock.get).toHaveBeenCalledTimes(1);
    expect(coreServiceMock.findApiKey).toHaveBeenCalled();
  });

  it('should pass if API key has necessary permission', async () => {
    currentPermission = Permission.XYZ_SERVICE;
    const pass = await apiKeyGuard.canActivate(getExecutionContext(serviceKey));

    expect(pass).toBe(true);
    expect(reflectorMock.get).toHaveBeenCalledTimes(1);
    expect(coreServiceMock.findApiKey).toHaveBeenCalled();
  });
});

function getExecutionContext(key?: string) {
  const context = {
    getClass: () => ({}),
    switchToHttp: () => ({
      getRequest: () => ({
        headers: { [HeaderName.API_KEY]: key },
      }),
    }),
  } as ExecutionContext;
  return context;
}
