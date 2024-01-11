import { Body, Controller, Post, Request } from '@nestjs/common';
import { TopicService } from './topic.service';
import { CreateTopicDto } from './dto/create-topic.dto';
import { ProtectedRequest } from '../core/http/request';

@Controller('topic')
export class TopicController {
  constructor(private readonly topicService: TopicService) {}

  @Post()
  async create(
    @Request() request: ProtectedRequest,
    @Body() createTopicDto: CreateTopicDto,
  ) {
    // await this.topicService.create(request.user, createTopicDto);
    return 'success';
  }
}
