import { Body, Controller, Post, Request } from '@nestjs/common';
import { MessageService } from './message.service';
import { CreateMessageDto } from './dto/create-message.dto';
import { Permissions } from '../auth/decorators/permissions.decorator';
import { Permission } from '../auth/schemas/apikey.schema';
import { ProtectedRequest } from '../core/http/request';
import { Roles } from '../auth/decorators/roles.decorator';
import { RoleCode } from '../auth/schemas/role.schema';

@Roles([RoleCode.VIEWER]) // Example: how to add roles on entire controller.
@Permissions([Permission.GENERAL]) // Example: how to add api key specific route restrictions.
@Controller('contact')
export class MessageController {
  constructor(private readonly messageService: MessageService) {}

  @Post()
  async create(
    @Request() request: ProtectedRequest,
    @Body() createMessageDto: CreateMessageDto,
  ) {
    await this.messageService.create(request.user, createMessageDto);
    return 'Message received successfully!';
  }
}
