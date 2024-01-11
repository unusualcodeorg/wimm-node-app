import { Controller, Get, NotFoundException, Param } from '@nestjs/common';
import { MentorService } from './mentor.service';
import { Types } from 'mongoose';
import { MentorDto } from './dto/mentor.dto';

@Controller('mentor')
export class MentorController {
  constructor(private readonly mentorService: MentorService) {}

  @Get('id/:id')
  async findOne(@Param('id') id: string) {
    const mentor = await this.mentorService.findById(new Types.ObjectId(id));
    if (!mentor) throw new NotFoundException('Mentor not found');

    // const subscription = await SubscriptionRepo.findSubscriptionForUser(
    //   req.user,
    // );

    // const subscribedTopic = subscription?.topics.find((m) =>
    //   mentor._id.equals(m._id),
    // );

    // const data = { ...mentor, subscribed: subscribedTopic !== undefined };
    return new MentorDto(mentor, false);
  }
}
