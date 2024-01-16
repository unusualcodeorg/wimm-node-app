import {
  Body,
  Controller,
  Get,
  InternalServerErrorException,
  NotFoundException,
  Param,
  Post,
  Query,
  Request,
} from '@nestjs/common';
import { SubscriptionService } from './subscription.service';
import { SubscriptionDto } from './dto/subscription.dto';
import { ProtectedRequest } from '../core/http/request';
import { MentorInfoDto } from '../mentor/dto/mentor-info.dto';
import { TopicInfoDto } from '../topic/dto/topic-info.dto';
import { MongoIdTransformer } from '../common/mongoid.transformer';
import { Types } from 'mongoose';
import { Category } from '../content/schemas/content.schema';
import { SubscriptionInfoDto } from './dto/subscription-info.dto';
import { PaginationDto } from '../common/pagination.dto';

@Controller('subscription')
export class SubscriptionController {
  constructor(private readonly subscriptionService: SubscriptionService) {}

  @Post('subscribe')
  async subscribe(
    @Request() request: ProtectedRequest,
    @Body() subscriptionDto: SubscriptionDto,
  ): Promise<string> {
    const subscription = await this.subscriptionService.processSubscription(
      request.user,
      subscriptionDto,
      'SUBSCRIBE',
    );
    if (!subscription) throw new InternalServerErrorException();
    return 'Followed Successfully';
  }

  @Post('unsubscribe')
  async unsubscribe(
    @Request() request: ProtectedRequest,
    @Body() subscriptionDto: SubscriptionDto,
  ): Promise<string> {
    const subscription = await this.subscriptionService.processSubscription(
      request.user,
      subscriptionDto,
      'UNSUBSCRIBE',
    );
    if (!subscription) throw new InternalServerErrorException();
    return 'Unfollowed Successfully';
  }

  @Get('mentors')
  async subscriptionMentors(@Request() request: ProtectedRequest) {
    const subscription = await this.subscriptionService.findSubscribedMentors(
      request.user,
    );
    if (!subscription)
      throw new NotFoundException('You have not subscribed to any Mentor');

    return subscription.mentors.map((m) => new MentorInfoDto(m));
  }

  @Get('topics')
  async subscriptionTopics(@Request() request: ProtectedRequest) {
    const subscription = await this.subscriptionService.findSubscribedTopics(
      request.user,
    );
    if (!subscription)
      throw new NotFoundException('You have not subscribed to any Topic');

    return subscription.topics.map((t) => new TopicInfoDto(t));
  }

  @Get('info/mentor/:id')
  async mentorInfo(
    @Param('id', MongoIdTransformer) mentorId: Types.ObjectId,
    @Request() request: ProtectedRequest,
  ) {
    const exits = await this.subscriptionService.mentorSubscriptionExists(
      request.user,
      mentorId,
    );

    return new SubscriptionInfoDto({
      itemId: mentorId,
      category: Category.MENTOR_INFO,
      subscribed: exits,
    });
  }

  @Get('info/topic/:id')
  async topicInfo(
    @Param('id', MongoIdTransformer) topicId: Types.ObjectId,
    @Request() request: ProtectedRequest,
  ) {
    const exits = await this.subscriptionService.topicSubscriptionExists(
      request.user,
      topicId,
    );

    return new SubscriptionInfoDto({
      itemId: topicId,
      category: Category.TOPIC_INFO,
      subscribed: exits,
    });
  }

  @Get('recommendation/mentors')
  async recommendedMentors(
    @Query() paginationDto: PaginationDto,
    @Request() request: ProtectedRequest,
  ) {
    return this.subscriptionService.findRecommendedMentors(
      request.user,
      paginationDto,
    );
  }

  @Get('recommendation/topics')
  async recommendedTopics(
    @Query() paginationDto: PaginationDto,
    @Request() request: ProtectedRequest,
  ) {
    return this.subscriptionService.findRecommendedTopics(
      request.user,
      paginationDto,
    );
  }
}
