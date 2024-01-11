import { Controller, Get, Param, Request } from '@nestjs/common';
import { TopicService } from './topic.service';
import { Types } from 'mongoose';
import { ProtectedRequest } from '../core/http/request';
import { TopicSubscriptionDto } from './dto/topic-subsciption.dto';
import { MongoIdTransformer } from '../common/mongoid.transformer';

@Controller('topic')
export class TopicController {
  constructor(private readonly topicService: TopicService) {}

  @Get('id/:id')
  async findOne(
    @Param('id', MongoIdTransformer) id: Types.ObjectId,
    @Request() request: ProtectedRequest,
  ): Promise<TopicSubscriptionDto> {
    return this.topicService.findTopicSubsciption(id, request.user);
  }
}
