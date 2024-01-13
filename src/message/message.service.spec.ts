import { Test } from '@nestjs/testing';
import { MessageService } from './message.service';
import { User } from '../user/schemas/user.schema';
import { CreateMessageDto } from './dto/create-message.dto';
import { getModelToken } from '@nestjs/mongoose';
import { Message } from './schemas/message.schema';

describe('MessageService', () => {
  let messageService: MessageService;

  const mockMessage = { message: 'message' } as Message;

  beforeEach(async () => {
    const moduleRef = await Test.createTestingModule({
      providers: [
        MessageService,
        {
          provide: getModelToken(Message.name),
          useValue: {
            create: jest.fn().mockReturnValue(mockMessage),
          },
        },
      ],
    }).compile();

    messageService = moduleRef.get(MessageService);
  });

  describe('create', () => {
    const mockUser = {} as User;
    const mockCreateMessageDto = { message: 'message' } as CreateMessageDto;
    it('should create a Message when CreateMessageDto is sent', async () => {
      jest.spyOn(messageService, 'create');

      expect(
        messageService.create(mockUser, mockCreateMessageDto),
      ).resolves.toStrictEqual(mockCreateMessageDto);

      expect(messageService.create).toHaveBeenCalledWith(
        mockUser,
        mockCreateMessageDto,
      );
    });
  });
});
