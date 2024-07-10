import { Test } from '@nestjs/testing';
import { AuthService } from './auth.service';
import { ApiKey } from './schemas/apikey.schema';
import { getModelToken } from '@nestjs/mongoose';
import { Keystore } from './schemas/keystore.schema';
import { Role } from './schemas/role.schema';
import { JwtService } from '@nestjs/jwt';
import { UserService } from '../user/user.service';
import { ConfigService } from '@nestjs/config';

describe('AuthService', () => {
  const validKey = 'api_key';
  const expectedResult = {
    key: 'api_key',
    status: true,
  };

  const findOneMockFn = jest.fn(({ key }) => ({
    lean: jest.fn(() => ({
      exec: jest.fn(() => (key === validKey ? expectedResult : null)),
    })),
  }));

  let keyService: AuthService;

  beforeEach(async () => {
    findOneMockFn.mockClear();
    const module = await Test.createTestingModule({
      providers: [
        AuthService,
        {
          provide: getModelToken(ApiKey.name),
          useValue: {
            findOne: findOneMockFn,
          },
        },
        {
          provide: getModelToken(Keystore.name),
          useValue: {},
        },
        {
          provide: getModelToken(Role.name),
          useValue: {},
        },
        {
          provide: getModelToken(Role.name),
          useValue: {},
        },
        {
          provide: JwtService,
          useValue: {},
        },
        {
          provide: UserService,
          useValue: {},
        },
        {
          provide: ConfigService,
          useValue: {},
        },
      ],
    }).compile();
    keyService = module.get(AuthService);
  });

  it('should return the API key if correct key is sent', async () => {
    const result = await keyService.findApiKey(validKey);
    expect(result).toEqual(expectedResult);
    expect(findOneMockFn).toHaveBeenCalledWith({
      key: validKey,
      status: true,
    });
  });

  it('should return null if wrong key is sent', async () => {
    const wrongKey = 'api_key_1';
    const result = await keyService.findApiKey(wrongKey);
    expect(result).toBeNull();
    expect(findOneMockFn).toHaveBeenCalledWith({
      key: wrongKey,
      status: true,
    });
  });
});
