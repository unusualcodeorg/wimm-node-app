import { Body, Controller, Post } from '@nestjs/common';
import { MessageService } from './message.service';
import { CreateMessageDto } from './dto/create-message.dto';
import { MessageResponse } from '../core/response';

@Controller('contact')
export class MessageController {
  constructor(private readonly messageService: MessageService) {}

  @Post()
  async create(@Body() createMessageDto: CreateMessageDto) {
    await this.messageService.create(createMessageDto);
    return new MessageResponse('Message received successfully!');
  }
}
