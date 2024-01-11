import { Controller, Get, Query } from '@nestjs/common';
import { TopicService } from './topic.service';
import { TopicInfoDto } from './dto/topic-info.dto';
import { PaginationDto } from '../common/pagination.dto';

@Controller('topics')
export class TopicsController {
  constructor(private readonly topicService: TopicService) {}

  @Get('latest')
  async findLatest(
    @Query() paginationDto: PaginationDto,
  ): Promise<TopicInfoDto[]> {
    return this.topicService.findTopicsPaginated(paginationDto);
  }

  @Get('recommendation')
  async findRecomended(
    @Query() paginationDto: PaginationDto,
  ): Promise<TopicInfoDto[]> {
    return this.topicService.findRecommendedTopicsPaginated(paginationDto);
  }
}
