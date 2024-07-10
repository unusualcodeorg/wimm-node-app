import { Test, TestingModule } from '@nestjs/testing';
import { ApiKeyGuard } from './apikey.guard';
import { Reflector } from '@nestjs/core';
import { ExecutionContext, ForbiddenException } from '@nestjs/common';
import { ApiKey, Permission } from '../../auth/schemas/apikey.schema';
import { AuthService } from '../auth.service';
import { HeaderName } from '../../core/http/header';

describe('ApiKeyGuard', () => {
  let apiKeyGuard: ApiKeyGuard;

  const generalKey = 'general';
  const serviceKey = 'service';

  const generalApikey = {
    key: generalKey,
    permissions: [Permission.GENERAL],
  } as ApiKey;

  const serviceApikey = {
    key: serviceKey,
    permissions: [Permission.XYZ_SERVICE],
  } as ApiKey;

  const findApiKeyMock = jest.fn();
  const reflectorGetMock = jest.fn();

  beforeEach(async () => {
    jest.clearAllMocks();
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        ApiKeyGuard,
        { provide: AuthService, useValue: { findApiKey: findApiKeyMock } },
        { provide: Reflector, useValue: { get: reflectorGetMock } },
      ],
    }).compile();

    apiKeyGuard = module.get(ApiKeyGuard);
  });

  it('should throw ForbiddenException if API key is not sent', async () => {
    await expect(
      apiKeyGuard.canActivate(getExecutionContext()),
    ).rejects.toBeInstanceOf(ForbiddenException);

    expect(reflectorGetMock).toHaveBeenCalledTimes(1);
    expect(findApiKeyMock).not.toHaveBeenCalled();
  });

  it('should throw ForbiddenException if wrong API key is sent', async () => {
    const currentKey = 'wrong';
    findApiKeyMock.mockReturnValue(null);

    await expect(
      apiKeyGuard.canActivate(getExecutionContext(currentKey)),
    ).rejects.toBeInstanceOf(ForbiddenException);

    expect(reflectorGetMock).toHaveBeenCalledTimes(1);
    expect(findApiKeyMock).toHaveBeenCalledWith(currentKey);
  });

  it('should throw ForbiddenException if API key does not have permission', async () => {
    reflectorGetMock.mockReturnValue([Permission.GENERAL]);
    findApiKeyMock.mockReturnValue(serviceApikey);

    await expect(
      apiKeyGuard.canActivate(getExecutionContext(serviceKey)),
    ).rejects.toBeInstanceOf(ForbiddenException);

    expect(reflectorGetMock).toHaveBeenCalledTimes(1);
    expect(findApiKeyMock).toHaveBeenCalledWith(serviceKey);
  });

  it('should pass if API key has general permission', async () => {
    reflectorGetMock.mockReturnValue([Permission.GENERAL]);
    findApiKeyMock.mockReturnValue(generalApikey);

    const pass = await apiKeyGuard.canActivate(getExecutionContext(generalKey));

    expect(pass).toBe(true);
    expect(reflectorGetMock).toHaveBeenCalledTimes(1);
    expect(findApiKeyMock).toHaveBeenCalledWith(generalKey);
  });

  it('should pass if API key has necessary permission', async () => {
    reflectorGetMock.mockReturnValue([Permission.XYZ_SERVICE]);
    findApiKeyMock.mockReturnValue(serviceApikey);

    const pass = await apiKeyGuard.canActivate(getExecutionContext(serviceKey));

    expect(pass).toBe(true);
    expect(reflectorGetMock).toHaveBeenCalledTimes(1);
    expect(findApiKeyMock).toHaveBeenCalledWith(serviceKey);
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
