import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Transform, Type } from 'class-transformer';
import { ArrayMaxSize, ArrayMinSize, ArrayUnique, IsArray, IsBoolean, IsEmail, IsInt, IsOptional, IsString,
  IsUUID, Matches, Max, MaxLength, Min, MinLength, ValidateNested } from 'class-validator';

const Trim = () => Transform(({ value }: { value: unknown }) => typeof value === 'string' ? value.trim() : value);
const Canonical = () => Transform(({ value }: { value: unknown }) => typeof value === 'string' ? value.toLowerCase() : value);
export class CredentialsDto {
  @ApiProperty({ format: 'email', maxLength: 254 }) @IsEmail() @MaxLength(254) email!: string;
  @ApiProperty({ minLength: 12, maxLength: 128, format: 'password', writeOnly: true }) @IsString() @MinLength(12) @MaxLength(128) password!: string;
}
export class CharacterDto {
  @ApiProperty({ maxLength: 80, minLength: 1 }) @Trim() @IsString() @MinLength(1) @MaxLength(80) name!: string;
  @ApiProperty({ maxLength: 8000 }) @IsString() @MaxLength(8000) background!: string;
  @ApiProperty({ maxLength: 2000 }) @IsString() @MaxLength(2000) style!: string;
}
export class UpdateCharacterDto extends CharacterDto {
  @ApiProperty({ minimum: 1, maximum: 2147483646 }) @IsInt() @Min(1) @Max(2147483646) revision!: number;
}
export class EntryDto {
  @ApiProperty({ minLength: 1, maxLength: 200 }) @Trim() @IsString() @MinLength(1) @MaxLength(200) title!: string;
  @ApiProperty({ minLength: 1, maxLength: 20000 }) @IsString() @Matches(/\S/u) @MaxLength(20000) body!: string;
}
export class UpdateEntryDto extends EntryDto {
  @ApiProperty({ minimum: 1, maximum: 2147483646 }) @IsInt() @Min(1) @Max(2147483646) revision!: number;
}
export class ShareDto {
  @ApiProperty() @IsBoolean() active!: boolean;
  @ApiProperty({ minimum: 1, maximum: 2147483646 }) @IsInt() @Min(1) @Max(2147483646) entryRevision!: number;
  @ApiProperty({ minimum: 0, maximum: 2147483646, description: '0 for a new grant, otherwise current grant revision.' })
  @IsInt() @Min(0) @Max(2147483646) revision!: number;
}
export class ConversationDto {
  @ApiPropertyOptional({ format: 'uuid' }) @IsOptional() @Canonical() @IsUUID('4') entryId?: string;
}
export class MessageDto {
  @ApiProperty({ minLength: 1, maxLength: 20000 }) @IsString() @Matches(/\S/u) @MaxLength(20000) body!: string;
}
export class SourceDto {
  @ApiProperty({ format: 'uuid' }) @Canonical() @IsUUID('4') entryId!: string;
  @ApiProperty({ minimum: 1, maximum: 2147483646 }) @IsInt() @Min(1) @Max(2147483646) revision!: number;
}
export class MemoryDto {
  @ApiProperty({ minLength: 1, maxLength: 4000 }) @IsString() @Matches(/\S/u) @MaxLength(4000) body!: string;
  @ApiProperty({ type: [SourceDto], minItems: 1, maxItems: 10 }) @IsArray() @ArrayMinSize(1) @ArrayMaxSize(10)
  @ArrayUnique((s: SourceDto) => s.entryId) @ValidateNested({ each: true }) @Type(() => SourceDto) sources!: SourceDto[];
  @ApiProperty() @IsBoolean() active!: boolean;
}
export class UpdateMemoryDto extends MemoryDto {
  @ApiProperty({ minimum: 1, maximum: 2147483646 }) @IsInt() @Min(1) @Max(2147483646) revision!: number;
}
export class PageDto {
  @ApiPropertyOptional({ minimum: 1, maximum: 100, default: 30 }) @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(100) limit = 30;
  @ApiPropertyOptional({ maxLength: 2048 }) @IsOptional() @IsString() @MaxLength(2048) cursor?: string;
}
export class EmptyDto {}
export class UserResponse {
  @ApiProperty({ format: 'uuid' }) id!: string;
  @ApiProperty({ format: 'email' }) email!: string;
}
export class AuthResponse {
  @ApiProperty() accessToken!: string;
  @ApiProperty({ format: 'date-time' }) expiresAt!: string;
  @ApiProperty({ type: UserResponse }) user!: UserResponse;
}
export class ResourceResponse {
  @ApiProperty({ format: 'uuid' }) id!: string;
  @ApiProperty({ format: 'date-time' }) createdAt!: string;
}
export class CharacterResponse extends ResourceResponse {
  @ApiProperty() name!: string;
  @ApiProperty() background!: string;
  @ApiProperty() style!: string;
  @ApiProperty() revision!: number;
  @ApiProperty() contextVersion!: number;
  @ApiProperty({ format: 'date-time' }) updatedAt!: string;
}
export class EntryResponse extends ResourceResponse {
  @ApiProperty({ enum: ['user', 'character'], description: 'character entries are fictional.' }) author!: string;
  @ApiProperty({ type: String, nullable: true, format: 'uuid' }) characterId!: string | null;
  @ApiProperty() title!: string;
  @ApiProperty() body!: string;
  @ApiProperty() revision!: number;
  @ApiProperty({ type: Number, nullable: true }) contextVersion!: number | null;
  @ApiProperty({ format: 'date-time' }) updatedAt!: string;
}
export class GrantResponse extends ResourceResponse {
  @ApiProperty({ format: 'uuid' }) characterId!: string;
  @ApiProperty({ format: 'uuid' }) entryId!: string;
  @ApiProperty() entryRevision!: number;
  @ApiProperty() active!: boolean;
  @ApiProperty() revision!: number;
  @ApiProperty({ format: 'date-time' }) updatedAt!: string;
}
export class ConversationResponse extends ResourceResponse {
  @ApiProperty({ format: 'uuid' }) characterId!: string;
  @ApiProperty({ type: String, nullable: true, format: 'uuid' }) entryId!: string | null;
}
export class MessageResponse extends ResourceResponse {
  @ApiProperty({ format: 'uuid' }) characterId!: string;
  @ApiProperty({ format: 'uuid' }) conversationId!: string;
  @ApiProperty({ enum: ['user', 'assistant'] }) role!: string;
  @ApiProperty() body!: string;
  @ApiProperty() sequence!: number;
  @ApiProperty() contextVersion!: number;
  @ApiProperty({ type: String, nullable: true, format: 'uuid' }) jobId!: string | null;
}
export class MemoryResponse extends ResourceResponse {
  @ApiProperty({ format: 'uuid' }) characterId!: string;
  @ApiProperty() body!: string;
  @ApiProperty({ type: [SourceDto] }) sources!: SourceDto[];
  @ApiProperty() active!: boolean;
  @ApiProperty() revision!: number;
  @ApiProperty({ format: 'date-time' }) updatedAt!: string;
}
export class JobResponse extends ResourceResponse {
  @ApiProperty({ format: 'uuid' }) characterId!: string;
  @ApiProperty({ type: String, nullable: true, format: 'uuid' }) conversationId!: string | null;
  @ApiProperty({ type: String, nullable: true, format: 'uuid' }) userMessageId!: string | null;
  @ApiProperty({ enum: ['reply', 'diary'] }) kind!: string;
  @ApiProperty({ enum: ['pending', 'running', 'succeeded', 'failed', 'cancelled'] }) status!: string;
  @ApiProperty() contextVersion!: number;
  @ApiProperty() attempt!: number;
  @ApiProperty({ type: String, nullable: true, format: 'uuid' }) resultId!: string | null;
  @ApiProperty({ type: String, nullable: true }) errorCode!: string | null;
  @ApiProperty({ type: [SourceDto] }) sources!: SourceDto[];
  @ApiProperty({ format: 'date-time' }) updatedAt!: string;
}
export class OperationResponse extends ResourceResponse {
  @ApiProperty() operation!: string;
  @ApiProperty({ enum: ['characters', 'entries', 'grants', 'conversations', 'messages', 'memories', 'jobs'] }) resourceKind!: string;
  @ApiProperty({ format: 'uuid' }) resourceId!: string;
}
export class CapabilitiesResponse {
  @ApiProperty() generationAvailable!: boolean;
  @ApiProperty() provider!: string;
}
export class ErrorDetail {
  @ApiProperty() code!: string;
  @ApiProperty() message!: string;
  @ApiProperty({ format: 'uuid' }) requestId!: string;
}
export class ErrorResponse { @ApiProperty({ type: ErrorDetail }) error!: ErrorDetail }
