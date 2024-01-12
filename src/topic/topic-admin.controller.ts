import {
  Body,
  Controller,
  Delete,
  Param,
  Post,
  Put,
  Request,
} from '@nestjs/common';
import { TopicService } from './topic.service';
import { CreateTopicDto } from './dto/create-topic.dto';
import { Roles } from '../auth/decorators/roles.decorator';
import { RoleCode } from '../auth/schemas/role.schema';
import { ProtectedRequest } from '../core/http/request';
import { UpdateTopicDto } from './dto/update-topic.dto';
import { Types } from 'mongoose';
import { MongoIdTransformer } from '../common/mongoid.transformer';

@Roles([RoleCode.ADMIN])
@Controller('topic/admin')
export class TopicAdminController {
  constructor(private readonly topicService: TopicService) {}

  @Post()
  async create(
    @Request() request: ProtectedRequest,
    @Body() createTopicDto: CreateTopicDto,
  ) {
    return await this.topicService.create(request.user, createTopicDto);
  }

  @Put('id/:id')
  async update(
    @Param('id', MongoIdTransformer) id: Types.ObjectId,
    @Request() request: ProtectedRequest,
    @Body() updateTopicDto: UpdateTopicDto,
  ) {
    return await this.topicService.update(request.user, id, updateTopicDto);
  }

  @Delete('id/:id')
  async delete(@Param('id', MongoIdTransformer) id: Types.ObjectId) {
    return await this.topicService.delete(id);
  }
}
