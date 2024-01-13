import { Test } from '@nestjs/testing';
import { CoreService } from './core.service';
import { ApiKey } from './schemas/apikey.schema';
import { getModelToken } from '@nestjs/mongoose';

describe('CoreService', () => {
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

  let coreService: CoreService;

  beforeEach(async () => {
    findOneMockFn.mockClear();
    const module = await Test.createTestingModule({
      providers: [
        CoreService,
        {
          provide: getModelToken(ApiKey.name),
          useValue: {
            findOne: findOneMockFn,
          },
        },
      ],
    }).compile();
    coreService = module.get(CoreService);
  });

  it('should return the API key if correct key is sent', async () => {
    const result = await coreService.findApiKey(validKey);
    expect(result).toEqual(expectedResult);
    expect(findOneMockFn).toHaveBeenCalledWith({
      key: validKey,
      status: true,
    });
  });

  it('should return null if wrong key is sent', async () => {
    const wrongKey = 'api_key_1';
    const result = await coreService.findApiKey(wrongKey);
    expect(result).toBeNull();
    expect(findOneMockFn).toHaveBeenCalledWith({
      key: wrongKey,
      status: true,
    });
  });
});
