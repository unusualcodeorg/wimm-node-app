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
  const restrictedKey = 'restricted';
  let currentKey = '';

  const generalApikey = {
    key: generalKey,
    permissions: [Permission.GENERAL],
  } as ApiKey;

  const serviceApikey = {
    key: serviceKey,
    permissions: [Permission.XYZ_SERVICE],
  } as ApiKey;

  const restrictedApikey = {
    key: restrictedKey,
    permissions: [Permission.XYZ_SERVICE],
  } as ApiKey;

  const coreServiceMock = {
    findApiKey: jest.fn((key) => {
      switch (key) {
        case generalKey:
          return generalApikey;
        case serviceKey:
          return serviceApikey;
        case restrictedKey:
          return restrictedApikey;
        default:
          return null;
      }
    }),
  };
  const reflectorMock = {
    get: jest.fn(() => {
      switch (currentKey) {
        case generalKey:
          return [Permission.GENERAL];
        case serviceKey:
          return [Permission.XYZ_SERVICE];
        case restrictedKey:
          return [Permission.GENERAL];
        default:
          return null;
      }
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
    apiKeyGuard
      .canActivate(getExecutionContext())
      .catch((e) => expect(e).toBeInstanceOf(ForbiddenException));

    expect(reflectorMock.get).toHaveBeenCalledTimes(1);
    expect(coreServiceMock.findApiKey).not.toHaveBeenCalled();
  });

  it('should throw ForbiddenException if wrong API key is sent', async () => {
    currentKey = 'wrong';
    apiKeyGuard
      .canActivate(getExecutionContext(currentKey))
      .catch((e) => expect(e).toBeInstanceOf(ForbiddenException));

    expect(reflectorMock.get).toHaveBeenCalledTimes(1);
    expect(coreServiceMock.findApiKey).toHaveBeenCalledWith(currentKey);
  });

  it('should throw ForbiddenException if API key does not have permission', async () => {
    currentKey = serviceKey;
    apiKeyGuard
      .canActivate(getExecutionContext(currentKey))
      .catch((e) => expect(e).toBeInstanceOf(ForbiddenException));

    expect(reflectorMock.get).toHaveBeenCalledTimes(1);
    expect(coreServiceMock.findApiKey).toHaveBeenCalledWith(currentKey);
  });

  it('should throw ForbiddenException if API key has necessary permission', async () => {
    currentKey = restrictedKey;
    apiKeyGuard
      .canActivate(getExecutionContext(currentKey))
      .catch((e) => expect(e).toBeInstanceOf(ForbiddenException));

    expect(reflectorMock.get).toHaveBeenCalledTimes(1);
    expect(coreServiceMock.findApiKey).toHaveBeenCalledWith(currentKey);
  });

  it('should pass if API key has general permission', async () => {
    currentKey = generalKey;
    const pass = apiKeyGuard.canActivate(getExecutionContext(currentKey));

    expect(pass).resolves.toBe(true);
    expect(reflectorMock.get).toHaveBeenCalledTimes(1);
    expect(coreServiceMock.findApiKey).toHaveBeenCalledWith(currentKey);
  });

  it('should pass if API key has necessary permission', async () => {
    currentKey = serviceKey;
    const pass = apiKeyGuard.canActivate(getExecutionContext(currentKey));

    expect(pass).resolves.toBe(true);
    expect(reflectorMock.get).toHaveBeenCalledTimes(1);
    expect(coreServiceMock.findApiKey).toHaveBeenCalledWith(currentKey);
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
