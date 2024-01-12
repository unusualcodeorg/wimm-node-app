import { Controller, Get, NotFoundException, Param } from '@nestjs/common';
import { Types } from 'mongoose';
import { MongoIdTransformer } from '../common/mongoid.transformer';
import { TopicService } from './topic.service';
import { TopicInfoDto } from './dto/topic-info.dto';

@Controller('topic')
export class TopicController {
  constructor(private readonly topicService: TopicService) {}

  @Get('id/:id')
  async findOne(
    @Param('id', MongoIdTransformer) id: Types.ObjectId,
  ): Promise<TopicInfoDto> {
    const topic = await this.topicService.findById(id);
    if (!topic) throw new NotFoundException('Topic Not Found');
    return new TopicInfoDto(topic);
  }
}
