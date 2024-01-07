import { Injectable } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model } from 'mongoose';
import { Message } from './schemas/message.schema';
import { CreateMessageDto } from './dto/create-message.dto';
import { User } from '../user/schemas/user.schema';

@Injectable()
export class MessageService {
  constructor(
    @InjectModel(Message.name) private readonly messageModel: Model<Message>,
  ) {}

  async create(
    user: User,
    createMessageDto: CreateMessageDto,
  ): Promise<Message> {
    const message = await this.messageModel.create({
      ...createMessageDto,
      user: user,
    });
    return message;
  }
}
